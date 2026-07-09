defmodule HeadsUpWeb.CoinController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Coins

  plug :put_view, json: HeadsUpWeb.CoinJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/coins — the wallet: balance + recent movements.
  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, balance: Coins.balance(user.id), entries: Coins.history(user.id))
  end
end
