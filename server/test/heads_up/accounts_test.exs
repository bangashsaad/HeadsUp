defmodule HeadsUp.AccountsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.Accounts
  alias HeadsUp.Accounts.User

  defp user(attrs \\ %{}) do
    {:ok, u} =
      Accounts.register_user(
        Map.merge(%{"username" => "changer", "email" => "c@example.com", "password" => "oldpassword1"}, attrs)
      )

    u
  end

  describe "update_user_password/3" do
    test "changes the password when the current password is correct" do
      u = user()
      assert {:ok, updated} = Accounts.update_user_password(u, "oldpassword1", %{"password" => "newpassword2"})
      refute updated.hashed_password == u.hashed_password
      assert User.valid_password?(updated, "newpassword2")
      refute User.valid_password?(updated, "oldpassword1")
    end

    test "rejects a wrong current password (no change)" do
      u = user()
      assert {:error, :invalid_current_password} =
               Accounts.update_user_password(u, "wrongpass", %{"password" => "newpassword2"})

      assert User.valid_password?(u, "oldpassword1")
    end

    test "validates the new password length" do
      u = user()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user_password(u, "oldpassword1", %{"password" => "short"})
    end
  end
end
