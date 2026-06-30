defmodule HeadsUpWeb.GameJSON do
  def upcoming(%{games: games}), do: %{games: games}
end
