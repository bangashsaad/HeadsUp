defmodule HeadsUp.Sports.Injuries do
  @moduledoc """
  Who is hurt, keyed by ESPN athlete id — the same id we store as
  `players.external_id`, so it joins straight onto the draft board.

  This exists because projection is a SEASON AVERAGE: a star who got hurt
  last week still sits at the top of the board looking elite. Drafting them
  is a guaranteed zero, and it happened to real players before this shipped
  (Kelsey Plum, 36.6 projected, out with a leg injury).

  The feed gives no athlete id field, but each entry's headshot URL ends in
  `/full/<id>.png` — a far more reliable join than matching display names.

  Statuses collapse to two buckets the draft board can act on:

    * `:out` — will not play. Every IL variant, suspensions, bereavement.
    * `:questionable` — might play. Day-to-day, probable, questionable.

  Fails OPEN: an unreachable feed yields `%{}`, so the board simply shows no
  badges rather than blocking a draft.
  """

  require Logger

  alias HeadsUp.Sports.Espn.Client

  @ttl_ms 10 * 60 * 1000

  @doc """
  `%{external_id => %{status: :out | :questionable, label: "OUT", detail: "Right Leg", return_date: "2026-08-10"}}`
  for a sport. Cached ~10 minutes; injury news moves faster than rosters do.
  """
  @spec for_sport(String.t(), keyword()) :: %{optional(String.t()) => map()}
  def for_sport(sport, opts \\ []) do
    case Keyword.get(opts, :client) do
      nil -> cached(sport)
      client -> fetch(client, sport)
    end
  end

  @doc "This player's injury entry, or nil. Reads the same cached report."
  def for_player(%{sport: sport, external_id: external_id})
      when is_binary(sport) and is_binary(external_id) do
    sport |> for_sport() |> Map.get(external_id)
  end

  def for_player(_), do: nil

  defp cached(sport) do
    key = {__MODULE__, sport}

    case :persistent_term.get(key, nil) do
      {ts, report} when is_map(report) ->
        if System.monotonic_time(:millisecond) - ts < @ttl_ms, do: report, else: refresh(key, sport)

      _ ->
        refresh(key, sport)
    end
  end

  defp refresh(key, sport) do
    report = fetch(client(), sport)
    # Only cache a real answer — a failed fetch must not blind the board for
    # ten minutes.
    if map_size(report) > 0, do: :persistent_term.put(key, {System.monotonic_time(:millisecond), report})
    report
  end

  defp fetch(client, sport) do
    with true <- Client.supported?(sport),
         {:ok, body} <- client.injuries(sport) do
      body
      |> Map.get("injuries", [])
      |> List.wrap()
      |> Enum.flat_map(&List.wrap(Map.get(&1, "injuries")))
      |> Enum.reduce(%{}, fn entry, acc ->
        case {athlete_id(entry), normalize(entry["status"])} do
          {id, {status, label}} when is_binary(id) ->
            Map.put(acc, id, %{
              status: status,
              label: label,
              detail: detail(entry),
              return_date: get_in(entry, ["details", "returnDate"])
            })

          _ ->
            acc
        end
      end)
    else
      _ ->
        Logger.info("injury report unavailable for #{sport} — board will show no badges")
        %{}
    end
  end

  # The feed carries no athlete id, but the headshot URL ends in /full/<id>.png.
  defp athlete_id(entry) do
    case get_in(entry, ["athlete", "headshot", "href"]) do
      href when is_binary(href) ->
        case Regex.run(~r{/full/(\d+)\.png}, href) do
          [_, id] -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ESPN's wording varies by league: basketball says "Out"/"Day-To-Day",
  # baseball says "10-Day-IL"/"60-Day-IL"/"bereavement". Anything unrecognized
  # is treated as questionable rather than hidden — better a soft warning than
  # a silent miss.
  defp normalize(nil), do: nil

  defp normalize(status) do
    s = String.downcase(status)

    cond do
      s =~ "out" -> {:out, "OUT"}
      s =~ "il" -> {:out, il_label(status)}
      s =~ "suspen" -> {:out, "SUSP"}
      s =~ "bereavement" -> {:out, "OUT"}
      s =~ "day-to-day" or s =~ "day to day" -> {:questionable, "GTD"}
      s =~ "questionable" -> {:questionable, "QUES"}
      s =~ "probable" -> {:questionable, "PROB"}
      true -> {:questionable, String.upcase(String.slice(status, 0, 4))}
    end
  end

  # "10-Day-IL" -> "IL-10" so the badge stays short but keeps the meaning.
  defp il_label(status) do
    case Regex.run(~r/(\d+)/, status) do
      [_, days] -> "IL-#{days}"
      _ -> "IL"
    end
  end

  defp detail(entry) do
    [get_in(entry, ["details", "side"]), get_in(entry, ["details", "type"])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> entry["shortComment"]
      text -> text
    end
  end

  defp client, do: Application.get_env(:heads_up, :injuries_client, Client)
end
