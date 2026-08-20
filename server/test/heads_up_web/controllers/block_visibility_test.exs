defmodule HeadsUpWeb.BlockVisibilityTest do
  @moduledoc "A blocked person cannot pull your record or profile by id — the API answers as if you don't exist."
  use HeadsUpWeb.ConnCase, async: true

  alias HeadsUp.{Accounts, Social}

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp as(conn, user) do
    token = Accounts.create_user_api_token(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  test "rivals and profiles 404 across a block, in both directions", %{conn: conn} do
    a = user("bva")
    b = user("bvb")

    assert conn |> as(b) |> get(~p"/api/rivals/#{a.id}") |> json_response(200)
    assert conn |> as(b) |> get(~p"/api/users/#{a.id}") |> json_response(200)

    {:ok, _} = Social.block_user(a, b.id)

    assert conn |> as(b) |> get(~p"/api/rivals/#{a.id}") |> json_response(404)
    assert conn |> as(b) |> get(~p"/api/users/#{a.id}") |> json_response(404)
    assert conn |> as(a) |> get(~p"/api/rivals/#{b.id}") |> json_response(404)
    assert conn |> as(a) |> get(~p"/api/users/#{b.id}") |> json_response(404)
  end
end
