defmodule HeadsUpWeb.GameJSON do
  def upcoming(%{games: games}), do: %{games: games}

  # The box score is already a plain map of maps/lists — render it as-is.
  def boxscore(%{box: box}), do: box
end
