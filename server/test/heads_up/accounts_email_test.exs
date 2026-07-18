defmodule HeadsUp.AccountsEmailTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.Accounts

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  # The Test adapter delivers synchronously to this process's mailbox.
  defp sent_code do
    assert_received {:email, email}
    [code] = Regex.run(~r/\b(\d{6})\b/, email.text_body, capture: :all_but_first)
    code
  end

  describe "email verification" do
    test "a fresh code verifies the account; junk doesn't" do
      u = user("verifyme")
      assert is_nil(u.email_verified_at)

      :ok = Accounts.deliver_email_verification(u)
      code = sent_code()

      assert {:error, :invalid_code} = Accounts.verify_email(u, "000000")
      assert {:ok, verified} = Accounts.verify_email(u, code)
      refute is_nil(verified.email_verified_at)

      # Codes are single-use.
      assert {:error, :invalid_code} = Accounts.verify_email(u, code)
    end

    test "resending replaces the old code" do
      u = user("resender")
      :ok = Accounts.deliver_email_verification(u)
      old_code = sent_code()
      :ok = Accounts.deliver_email_verification(u)
      new_code = sent_code()

      assert {:error, :invalid_code} = Accounts.verify_email(u, old_code)
      assert {:ok, _} = Accounts.verify_email(u, new_code)
    end
  end

  describe "password reset" do
    test "the full loop: code -> new password, sessions dead, email proven" do
      u = user("forgetful")
      api_token = Accounts.create_user_api_token(u)

      :ok = Accounts.deliver_password_reset("forgetful@example.com")
      code = sent_code()

      assert {:ok, _} = Accounts.reset_password("forgetful@example.com", code, "newpassword456")

      assert Accounts.get_user_by_email_and_password("forgetful@example.com", "password123") == nil
      assert %{id: id} = Accounts.get_user_by_email_and_password("forgetful@example.com", "newpassword456")
      assert id == u.id

      # Every old session is dead, and the inbox counts as verified now.
      assert Accounts.get_user_by_api_token(api_token) == nil
      refute is_nil(Accounts.get_user(u.id).email_verified_at)
    end

    test "a wrong code changes nothing" do
      user("careful")
      :ok = Accounts.deliver_password_reset("careful@example.com")
      _real = sent_code()

      assert {:error, :invalid_code} = Accounts.reset_password("careful@example.com", "111111", "hacked12345")
      assert Accounts.get_user_by_email_and_password("careful@example.com", "password123")
    end

    test "an unknown email is silently fine (no account enumeration)" do
      assert :ok = Accounts.deliver_password_reset("nobody@example.com")
      refute_received {:email, _}
    end

    test "a weak new password is rejected by the changeset" do
      user("weakling")
      :ok = Accounts.deliver_password_reset("weakling@example.com")
      code = sent_code()

      assert {:error, %Ecto.Changeset{}} = Accounts.reset_password("weakling@example.com", code, "short")
    end
  end
end
