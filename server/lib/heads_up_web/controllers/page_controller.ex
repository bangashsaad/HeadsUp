defmodule HeadsUpWeb.PageController do
  use HeadsUpWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
