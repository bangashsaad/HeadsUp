defmodule HeadsUpWeb.PageControllerTest do
  use HeadsUpWeb.ConnCase, async: true

  alias HeadsUp.Accounts
  alias HeadsUpWeb.UserAuth

  test "the front door pitches the product, not the framework", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Heads"
    assert html =~ "Challenge a friend"
    assert html =~ "/signup"
    # The stock Phoenix page is what shipped here by accident once.
    refute html =~ "Phoenix Framework"
    refute html =~ "phoenixframework.org"
  end

  test "a signed-in visitor is sent to their duels instead", %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "username" => "landing",
        "email" => "landing@example.com",
        "password" => "password123"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> UserAuth.log_in_web_user(user)
      |> get(~p"/")

    assert redirected_to(conn) == "/app"
  end
end
