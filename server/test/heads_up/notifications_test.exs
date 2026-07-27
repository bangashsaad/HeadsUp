defmodule HeadsUp.NotificationsTest do
  # async: false — swaps the Notifications app env per test.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Notifications}

  @stub HeadsUp.NotificationsTest.Stub

  setup do
    prev = Application.get_env(:heads_up, HeadsUp.Notifications)

    Application.put_env(:heads_up, HeadsUp.Notifications,
      enabled: true,
      push_url: "https://expo.test/push",
      req_options: [plug: {Req.Test, @stub}, retry: false]
    )

    on_exit(fn -> Application.put_env(:heads_up, HeadsUp.Notifications, prev) end)
    :ok
  end

  test "deliver/4 POSTs the Expo payload for a token" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["to"] == "ExponentPushToken[abc]"
      assert payload["title"] == "You won! 🏆"
      assert payload["body"] =~ "Final"
      assert payload["data"] == %{"type" => "result", "duel_id" => 7}

      Req.Test.json(conn, %{"data" => %{"status" => "ok"}})
    end)

    assert :ok =
             Notifications.deliver("ExponentPushToken[abc]", "You won! 🏆", "Final: 120 – 80", %{
               type: "result",
               duel_id: 7
             })
  end

  test "deliver/4 skips a nil token (user never registered a device)" do
    assert :skip = Notifications.deliver(nil, "t", "b", %{})
  end

  test "deliver/4 returns :error on a failed send without raising" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    assert :error = Notifications.deliver("ExponentPushToken[abc]", "t", "b", %{})
  end

  test "update_push_token stores and clears the device token" do
    {:ok, user} =
      Accounts.register_user(%{"username" => "pushuser", "email" => "push@example.com", "password" => "password123"})

    assert {:ok, updated} = Accounts.update_push_token(user, "ExponentPushToken[xyz]")
    assert updated.push_token == "ExponentPushToken[xyz]"

    assert {:ok, cleared} = Accounts.update_push_token(updated, nil)
    assert cleared.push_token == nil
  end
end
