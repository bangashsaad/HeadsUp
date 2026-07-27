defmodule HeadsUp.DevTools do
  @moduledoc """
  Developer-only conveniences for exercising the live stats pipeline. Guarded by
  the `:dev_routes` flag (true only in `dev.exs`) so these can never run in
  test/prod by accident.
  """
  import Ecto.Query, only: [from: 2]

  alias HeadsUp.Repo
  alias HeadsUp.Settlement
  alias HeadsUp.Contests.Duel

  # ET = UTC−4 for the whole WNBA season; matches Settlement.Stats.WnbaEspn.
  @et_offset_seconds 4 * 3600

  @doc """
  Settle a drafted duel against the WNBA games of one ET calendar `date` —
  draft players who actually played that night, then watch real boxscore points
  land. Repoints the duel's frozen scoring window to span that ET day (in UTC)
  and calls `Settlement.settle_duel/1`.

      iex> HeadsUp.DevTools.settle_on_date(42, ~D[2026-06-28])
      {:ok, %Result{}, %Duel{status: "settled"}}

  `date` may be a `Date` or `"YYYY-MM-DD"` string. Returns `{:ok, :already_settled}`
  if the duel is already settled, `{:error, {:not_drafted, status}}` otherwise.
  """
  @spec settle_on_date(integer(), Date.t() | String.t(), keyword()) ::
          {:ok, struct(), Duel.t()} | {:ok, Duel.t()} | {:ok, :already_settled} | {:error, term()}
  def settle_on_date(duel_id, date, _opts \\ []) do
    cond do
      not dev?() ->
        {:error, :dev_only}

      true ->
        with {:ok, date} <- to_date(date),
             {:ok, :repointed} <- repoint_if_drafted(duel_id, date) do
          case Settlement.settle_duel(duel_id) do
            # the worker may have settled between the repoint and here
            {:ok, %Duel{}} -> {:ok, :already_settled}
            other -> other
          end
        else
          :already_settled -> {:ok, :already_settled}
          {:not_drafted, status} -> {:error, {:not_drafted, status}}
          :not_found -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # --- internals ----------------------------------------------------------

  # Repoint the scoring window ATOMICALLY, only while the duel is still
  # "drafted" — so a concurrent settle (worker) can't be clobbered back to
  # drafted by a stale in-memory struct. No row matched -> tell the caller why.
  defp repoint_if_drafted(duel_id, %Date{} = date) do
    {opens, closes} = day_window(date)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    query = from(d in Duel, where: d.id == ^duel_id and d.status == "drafted")

    case Repo.update_all(query,
           set: [scoring_window_start: opens, scoring_window_end: closes, updated_at: now]
         ) do
      {1, _} ->
        {:ok, :repointed}

      {0, _} ->
        case Repo.get(Duel, duel_id) do
          nil -> :not_found
          %Duel{status: "settled"} -> :already_settled
          %Duel{status: status} -> {:not_drafted, status}
        end
    end
  end

  # The UTC bounds of one ET calendar day: 00:00:00 ET → 23:59:59 ET.
  defp day_window(%Date{} = date) do
    et_midnight = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    opens = DateTime.add(et_midnight, @et_offset_seconds, :second)
    closes = DateTime.add(opens, 24 * 3600 - 1, :second)
    {DateTime.truncate(opens, :second), DateTime.truncate(closes, :second)}
  end

  defp to_date(%Date{} = d), do: {:ok, d}
  defp to_date(s) when is_binary(s), do: Date.from_iso8601(s)
  defp to_date(_), do: {:error, :bad_date}

  defp dev?, do: Application.get_env(:heads_up, :dev_routes, false) == true
end
