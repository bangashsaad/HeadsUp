defmodule BoutWeb.PageController do
  use BoutWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
