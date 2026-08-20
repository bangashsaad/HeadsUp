defmodule HeadsUpWeb.PageController do
  use HeadsUpWeb, :controller

  @doc """
  The front door. Anyone already signed in goes straight to their duels —
  a logged-in user landing on a marketing page is a dead end.
  """
  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: "/app")
    else
      conn
      |> put_root_layout(false)
      |> put_layout(false)
      |> render(:home)
    end
  end
end
