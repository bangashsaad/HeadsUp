defmodule BoutWeb.CoinController do
  use BoutWeb, :controller

  alias Bout.Coins

  plug :put_view, json: BoutWeb.CoinJSON
  action_fallback BoutWeb.FallbackController

  # GET /api/coins — the wallet: balance + recent movements.
  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, balance: Coins.balance(user.id), entries: Coins.history(user.id))
  end
end
