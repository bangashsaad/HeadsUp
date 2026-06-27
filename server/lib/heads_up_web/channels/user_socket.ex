defmodule HeadsUpWeb.UserSocket do
  @moduledoc """
  The realtime socket for the mobile client. Authenticates with the SAME
  encoded API token the app stores in SecureStore (passed as the `token` socket
  param), mirroring `UserAuth.fetch_api_user/2` but for websockets.
  """
  use Phoenix.Socket

  channel "draft:*", HeadsUpWeb.DraftChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case HeadsUp.Accounts.get_user_by_api_token(token) do
      %HeadsUp.Accounts.User{} = user -> {:ok, assign(socket, :current_user_id, user.id)}
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # Per-user socket id so a user's sockets could be force-disconnected later.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user_id}"
end
