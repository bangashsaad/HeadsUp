defmodule Mix.Tasks.HeadsUp.SettleOnDate do
  @shortdoc "Dev-only: settle a drafted duel against one ET game date"
  @moduledoc """
  Settle a drafted duel against the WNBA games of one ET calendar day, so you
  can test the live ESPN settlement pipeline against a past final game.

      mix heads_up.settle_on_date <duel_id> <YYYY-MM-DD>

  Dev-only (guarded by `:dev_routes`). See `HeadsUp.DevTools.settle_on_date/3`.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run([duel_id, date]) do
    case HeadsUp.DevTools.settle_on_date(String.to_integer(duel_id), date) do
      {:ok, result, duel} ->
        Mix.shell().info("""
        Settled duel #{duel.id} (status: #{duel.status})
          winner_id:  #{inspect(duel.winner_id)}
          challenger: #{result.challenger_points}
          opponent:   #{result.opponent_points}
          tie?:       #{result.is_tie}
        """)

      {:ok, :already_settled} ->
        Mix.shell().info("Duel #{duel_id} was already settled — no-op.")

      {:error, reason} ->
        Mix.raise("settle_on_date failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("usage: mix heads_up.settle_on_date <duel_id> <YYYY-MM-DD>")
end
