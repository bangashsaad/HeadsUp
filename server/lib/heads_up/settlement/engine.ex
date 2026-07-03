defmodule HeadsUp.Settlement.Engine do
  @moduledoc """
  Pure fantasy-scoring + settlement math. Turns raw stat lines and a duel's
  FROZEN `scoring_rules` chart into fantasy points, per-user roster results, and
  a winner (or tie).

  No side effects — never touches the Repo, a provider, or the clock. The caller
  hands in the duel, the draft picks (`HeadsUp.Drafts.replay/1` shape), and the
  stats map, so every result is deterministic and unit-testable.

  Category keys are the same strings used in `Contests.Scoring` charts (e.g.
  "point", "passing_yards"); a category in the chart but absent from a player's
  stat line scores 0 (the locked draft-risk rule), as does a drafted player with
  no stat line at all (injured / benched / DNP).
  """
  alias HeadsUp.Contests.Duel

  @type stat_line :: %{optional(String.t()) => number()}
  @type rules :: %{optional(String.t()) => number()}
  @type pick :: %{user_id: integer(), player_id: integer(), pick_number: integer(), slot: String.t()}
  @type player_result :: %{player_id: integer(), slot: String.t(), points: float(), stat_line: stat_line()}
  @type roster_result :: %{user_id: integer(), total: float(), players: [player_result()]}
  @type settlement :: %{
          result: :win | :tie,
          winner_id: integer() | nil,
          challenger: roster_result(),
          opponent: roster_result()
        }

  @doc """
  Fantasy points for one stat line under a scoring chart: the sum over the
  CHART's categories of `stat_line[cat] * rules[cat]`. Missing categories (or a
  wholly empty/nil line) contribute 0. Raw float (not rounded).
  """
  @spec player_points(stat_line() | nil, rules()) :: float()
  def player_points(stat_line, rules) do
    line = stat_line || %{}

    Enum.reduce(rules, 0.0, fn {cat, weight}, acc ->
      acc + (Map.get(line, cat, 0) || 0) * weight
    end)
  end

  @doc """
  Score one user's roster. `picks` is that user's picks (replay/1 shape);
  `stats_by_player_id` maps player_id => stat_line (missing id => zero line).
  Players are returned in pick order; per-player points and the team total are
  rounded to 2 decimals.
  """
  @spec score_roster(integer(), [pick()], %{integer() => stat_line()}, rules()) :: roster_result()
  def score_roster(user_id, picks, stats_by_player_id, rules) do
    players =
      picks
      |> Enum.sort_by(& &1.pick_number)
      |> Enum.map(fn p ->
        stat_line = Map.get(stats_by_player_id, p.player_id, %{})

        %{
          player_id: p.player_id,
          slot: p.slot,
          points: round2(player_points(stat_line, rules)),
          stat_line: stat_line
        }
      end)

    total = players |> Enum.reduce(0.0, fn pr, acc -> acc + pr.points end) |> round2()
    %{user_id: user_id, total: total, players: players}
  end

  @doc """
  Settle a drafted duel. `draft_picks` is the full ordered pick list for both
  users; `stats_by_player_id` covers every drafted player. Equal (rounded)
  totals => tie.
  """
  @spec settle(Duel.t(), [pick()], %{integer() => stat_line()}) :: settlement()
  def settle(%Duel{} = duel, draft_picks, stats_by_player_id) do
    ranked =
      settle_ranked(
        duel.scoring_rules,
        [duel.challenger_id, duel.opponent_id],
        draft_picks,
        stats_by_player_id
      )

    find = fn uid -> ranked.standings |> Enum.find(&(&1.user_id == uid)) |> Map.delete(:rank) end

    %{
      result: ranked.result,
      winner_id: ranked.winner_id,
      challenger: find.(duel.challenger_id),
      opponent: find.(duel.opponent_id)
    }
  end

  @doc """
  Settle an N-player contest: score every roster, rank by total (competition
  ranking — equal totals share a rank), and declare the sole top scorer the
  winner (`winner_id` nil when first place is shared => `:tie`).
  """
  @spec settle_ranked(rules(), [integer()], [pick()], %{integer() => stat_line()}) :: %{
          result: :win | :tie,
          winner_id: integer() | nil,
          standings: [%{user_id: integer(), total: float(), rank: pos_integer(), players: [player_result()]}]
        }
  def settle_ranked(rules, player_user_ids, draft_picks, stats_by_player_id) do
    by_user = Enum.group_by(draft_picks, & &1.user_id)

    standings =
      player_user_ids
      |> Enum.map(&score_roster(&1, Map.get(by_user, &1, []), stats_by_player_id, rules))
      |> rank()

    top_shared = Enum.count(standings, &(&1.rank == 1)) > 1

    %{
      result: if(top_shared, do: :tie, else: :win),
      winner_id: if(top_shared, do: nil, else: hd(standings).user_id),
      standings: standings
    }
  end

  # Sort by total desc and assign competition ranks (100, 90, 90, 70 -> 1, 2, 2, 4).
  defp rank(rosters) do
    sorted = Enum.sort_by(rosters, & &1.total, :desc)

    sorted
    |> Enum.with_index()
    |> Enum.map_reduce(nil, fn {r, idx}, prev ->
      rank = if prev && prev.total == r.total, do: prev.rank, else: idx + 1
      entry = Map.put(r, :rank, rank)
      {entry, entry}
    end)
    |> elem(0)
  end

  defp round2(n), do: Float.round(n * 1.0, 2)
end
