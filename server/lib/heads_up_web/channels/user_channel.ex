defmodule HeadsUpWeb.UserChannel do
  @moduledoc """
  A user's personal feed: `user:<id>`. You may only join your own. Nothing is
  pushed *in*; the server fans `"duel_changed"` out (see `Contests.Events`)
  and the phone refetches whatever screen it's on.
  """
  use Phoenix.Channel

  @impl true
  def join("user:" <> id, _params, socket) do
    if to_string(socket.assigns.current_user_id) == id do
      {:ok, socket}
    else
      {:error, %{reason: "not yours"}}
    end
  end
end
