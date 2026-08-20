defmodule HeadsUpWeb.ShellHook do
  @moduledoc """
  Assigns everything the design's app shell renders around a page: the marquee
  ticker (live scores, finals, tonight's tips, your duel lines), the sidebar
  nav's duel count and LIVE flag with their targets, the coin wallet, and the
  record line under your name.

  The game half of the ticker is shared by every viewer, so it's cached in
  `persistent_term` for a minute — one ESPN sweep feeds every mount. The duel
  half is per-user and comes from one cheap DB read that also powers the nav
  badges, so the whole hook costs a couple of queries per navigation.
  """
  import Phoenix.Component, only: [assign: 3]

  alias HeadsUp.{Coins, Contests, Social, Stats}
  alias HeadsUp.Sports.Schedule

  @ticker_key {__MODULE__, :ticker}
  @ticker_ttl_ms 60_000
  @sports ~w(wnba mlb nfl)

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_user

    duels = Contests.list_duels(user)
    active = Enum.filter(duels, &(&1.status in ~w(pending accepted drafting drafted)))
    live_duel = Enum.find(active, &(&1.status == "drafted"))
    draft_duel = Enum.find(active, &(&1.status in ~w(accepted drafting)))

    shell = %{
      active: nav_key(socket.view),
      ticker: game_ticker() ++ duel_ticker(active, user.id),
      duel_count: length(active),
      live_path: (live_duel && "/app/live/#{live_duel.id}") || "/app/live",
      draft_path: (draft_duel && "/app/draft/#{draft_duel.id}") || "/app/draft",
      live?: live_duel != nil,
      coins: Coins.balance(user.id),
      record: Stats.record_for(user.id),
      req_count: length(Social.list_incoming_requests(user))
    }

    {:cont, assign(socket, :shell, shell)}
  end

  # --- the game half (shared, cached) ----------------------------------------

  @doc """
  The shared live-scores half of the marquee (cached one minute). Public
  because the phone gate page runs the same ticker without a session.
  """
  def game_ticker do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@ticker_key, nil) do
      {ts, entries} when now - ts < @ticker_ttl_ms ->
        entries

      _ ->
        entries = build_game_ticker()
        :persistent_term.put(@ticker_key, {now, entries})
        entries
    end
  end

  defp build_game_ticker do
    games =
      Enum.flat_map(@sports, fn sport ->
        case Schedule.upcoming(sport) do
          {:ok, list} -> list
          _ -> []
        end
      end)

    live = games |> Enum.filter(&(&1.state == "in")) |> Enum.take(4) |> Enum.map(&live_entry/1)
    final = games |> Enum.filter(&(&1.state == "post")) |> Enum.take(3) |> Enum.map(&final_entry/1)
    pre = games |> Enum.filter(&(&1.state == "pre")) |> Enum.take(6) |> Enum.map(&pre_entry/1)

    live ++ final ++ pre
  end

  defp live_entry(g) do
    %{
      tag: "● LIVE",
      tag_color: "#FF4557",
      line: "#{abbrev(g.away)} #{score(g.away)} — #{abbrev(g.home)} #{score(g.home)}",
      meta: g.status || ""
    }
  end

  defp final_entry(g) do
    %{
      tag: "FINAL",
      tag_color: "#565D73",
      line: "#{abbrev(g.away)} #{score(g.away)} — #{abbrev(g.home)} #{score(g.home)}",
      meta: ""
    }
  end

  defp pre_entry(g) do
    %{
      tag: g.status || "SOON",
      tag_color: "var(--acc,#C8FF2E)",
      line: "#{abbrev(g.away)} @ #{abbrev(g.home)}",
      meta: ""
    }
  end

  # --- the duel half (per user, cheap) ----------------------------------------

  defp duel_ticker(active, me) do
    active
    |> Enum.filter(&(&1.status == "drafted"))
    |> Enum.take(2)
    |> Enum.map(fn d ->
      %{tag: "DUEL", tag_color: "#7C5CFF", line: "you vs #{opponent_name(d, me)}", meta: "LIVE NOW"}
    end)
  end

  defp opponent_name(%{opponent_id: nil} = d, _me), do: "the #{length(d.participants)}-player table"

  defp opponent_name(d, me) do
    other = if d.challenger_id == me, do: d.opponent, else: d.challenger
    (other && other.username) || "them"
  end

  defp abbrev(nil), do: "—"
  defp abbrev(side), do: side.abbrev || "—"

  defp score(nil), do: ""
  defp score(side), do: side.score || "0"

  # Which sidebar item this LiveView is.
  defp nav_key(HeadsUpWeb.HomeLive), do: :home
  defp nav_key(HeadsUpWeb.DuelsLive), do: :duels
  defp nav_key(HeadsUpWeb.DuelDetailLive), do: :duels
  defp nav_key(HeadsUpWeb.DraftLive), do: :draft
  defp nav_key(HeadsUpWeb.DraftHubLive), do: :draft
  defp nav_key(HeadsUpWeb.LiveHubLive), do: :live
  defp nav_key(HeadsUpWeb.LiveLive), do: :live
  defp nav_key(HeadsUpWeb.GamesLive), do: :players
  defp nav_key(HeadsUpWeb.FriendsLive), do: :friends
  defp nav_key(HeadsUpWeb.YouLive), do: :profile
  defp nav_key(_), do: nil
end
