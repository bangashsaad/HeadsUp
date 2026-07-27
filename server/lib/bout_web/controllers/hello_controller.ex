defmodule BoutWeb.HelloController do
  use BoutWeb, :controller

  # GET /api/hello
  # Our very first endpoint: proves the phone can reach the server.
  def index(conn, _params) do
    json(conn, %{
      message: "Hello from the Bout server! 🏈🏀⚾️",
      status: "connected"
    })
  end
end
