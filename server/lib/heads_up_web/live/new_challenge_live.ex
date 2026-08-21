defmodule HeadsUpWeb.NewChallengeLive do
  @moduledoc """
  The challenge form in the design's two-column layout: term pickers on the
  left (league / roster / clock / slate / who answers, with friend-
  group tabs), and the sticky THE TERMS summary rail on the right with the
  send button. DOM and styles from the design export; the values and the
  payload are the app's, verbatim, into the same `Contests.create_challenge/2`.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUpWeb.Params

  alias HeadsUp.{Contests, Social, Stats}
  alias HeadsUp.Drafts.Lineup
  alias HeadsUp.Sports.{Season, Slate}

  @leagues [
    %{key: "wnba", label: "🏀 WNBA"},
    %{key: "mlb", label: "⚾️ MLB"},
    %{key: "nfl", label: "🏈 NFL"},
    %{key: "nba", label: "🏀 NBA"}
  ]
  @clocks [15, 30, 60]
  @max_rivals 4

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    playable = Season.statuses() |> Enum.filter(& &1.playable) |> MapSet.new(& &1.sport)
    counter = counter_duel(user, params["counter"])
    h2h = Stats.head_to_head(user.id)

    socket =
      socket
      |> assign(page_title: if(counter, do: "Counter offer", else: "New challenge"))
      |> assign(
        leagues: @leagues,
        clocks: @clocks,
        max_rivals: @max_rivals,
        playable: playable,
        friends: Social.list_friends(user),
        groups: Social.list_friend_groups(user),
        group_tab: "ALL",
        shapes_open: false,
        rec_by_id: Map.new(h2h, &{&1.opponent.id, "#{&1.wins}–#{&1.losses} vs you"}),
        counter: counter,
        error: nil
      )
      |> seed_terms(counter, playable)
      |> seed_rival(params)
      |> load_slates()
      |> resnap_roster()

    {:ok, socket}
  end

  defp counter_duel(_user, nil), do: nil

  defp counter_duel(user, id) do
    with {duel_id, ""} <- Integer.parse(id),
         %{status: "pending"} = duel <- Contests.get_duel(user, duel_id) do
      duel
    else
      _ -> nil
    end
  end

  defp seed_terms(socket, nil, playable) do
    league = Enum.find_value(@leagues, "wnba", &if(MapSet.member?(playable, &1.key), do: &1.key))
    sizes = Lineup.sizes_for(league)
    assign(socket, league: league, rosters: sizes, roster: hd(sizes), clock: 30, rivals: [])
  end

  defp seed_terms(socket, duel, _playable) do
    sizes = Lineup.sizes_for(duel.sport)

    assign(socket,
      league: duel.sport,
      rosters: sizes,
      # Countering a legacy-size duel (mlb_5/mlb_7) re-terms onto today's menu.
      roster: if(duel.roster_size in sizes, do: duel.roster_size, else: hd(sizes)),
      clock: if(duel.pick_clock_seconds in @clocks, do: duel.pick_clock_seconds, else: 30),
      rivals: [duel.challenger_id]
    )
  end

  # ?rival=<id> — the profile's CHALLENGE button lands here with the rival
  # pre-picked, same as the phone's preselect.
  defp seed_rival(socket, %{"rival" => id}) do
    with {rid, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.friends, &(&1.id == rid)) do
      assign(socket, rivals: [rid])
    else
      _ -> socket
    end
  end

  defp seed_rival(socket, _params), do: socket

  defp load_slates(socket) do
    league = socket.assigns.league

    {kind, slates} =
      if Slate.week_shaped?(league) do
        case Slate.weeks(league) do
          {:ok, weeks} -> {"week", weeks}
          _ -> {"week", []}
        end
      else
        case Slate.upcoming(league) do
          {:ok, days} -> {"day", Enum.filter(days, &(&1.upcoming > 0))}
          _ -> {"day", []}
        end
      end

    default =
      case slates do
        [first | _] -> slate_id(kind, first)
        [] -> nil
      end

    slates =
      slates
      |> Enum.take(5)
      |> Enum.map(&Map.put(&1, :players, Contests.slate_player_count(league, &1.upcoming_teams)))

    assign(socket, slate_kind: kind, slates: slates, slate: default)
  end

  defp slate_id("week", w), do: w.key
  defp slate_id("day", d), do: Date.to_iso8601(d.date)

  # --- events ----------------------------------------------------------------

  @impl true
  def handle_event("league", %{"key" => key}, socket) do
    if MapSet.member?(socket.assigns.playable, key) do
      sizes = Lineup.sizes_for(key)
      roster = if socket.assigns.roster in sizes, do: socket.assigns.roster, else: hd(sizes)

      {:noreply, socket |> assign(league: key, rosters: sizes, roster: roster) |> load_slates() |> resnap_roster()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("roster", %{"n" => n}, socket) do
    n = Params.int(n)

    if roster_ok?(socket.assigns, n),
      do: {:noreply, assign(socket, roster: n, error: nil)},
      else: {:noreply, socket}
  end

  def handle_event("shapes-toggle", _params, socket), do: {:noreply, update(socket, :shapes_open, &(!&1))}

  def handle_event("clock", %{"n" => n}, socket), do: {:noreply, assign(socket, clock: Params.int(n))}

  def handle_event("slate", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(slate: id, error: nil) |> resnap_roster()}
  def handle_event("group", %{"g" => g}, socket), do: {:noreply, assign(socket, group_tab: g)}

  def handle_event("rival", %{"id" => id}, socket) do
    if socket.assigns.counter do
      {:noreply, socket}
    else
      id = Params.int(id)
      rivals = socket.assigns.rivals

      cond do
        id in rivals ->
          {:noreply, socket |> assign(rivals: List.delete(rivals, id), error: nil) |> resnap_roster()}

        length(rivals) >= @max_rivals ->
          {:noreply, assign(socket, error: "#{@max_rivals} rivals max — #{@max_rivals + 1} drafters per duel.")}

        not fits?(socket.assigns, socket.assigns.roster, max(length(rivals) + 2, 2)) ->
          {:noreply,
           assign(socket,
             error: "This slate can't field a #{socket.assigns.roster}-slot draft for #{length(rivals) + 2} players."
           )}

        true ->
          {:noreply, socket |> assign(rivals: rivals ++ [id], error: nil) |> resnap_roster()}
      end
    end
  end

  def handle_event("send", _params, socket) do
    %{league: league, roster: roster, clock: clock, rivals: rivals} = socket.assigns

    cond do
      not HeadsUpWeb.UserAuth.verified_for_duels?(socket.assigns.current_user) ->
        {:noreply,
         socket
         |> put_flash(:error, "Verify your email to duel — takes a few seconds.")
         |> push_navigate(to: "/app/verify")}

      rivals == [] ->
        {:noreply, assign(socket, error: "Pick at least one rival.")}

      not roster_ok?(socket.assigns, roster) ->
        {:noreply,
         assign(socket,
           error: "This slate can't field a #{roster}-slot draft for #{length(rivals) + 1} players."
         )}

      true ->
        attrs =
          %{
            "sport" => league,
            "lineup_template" => "#{league}_#{roster}",
            "roster_size" => roster,
            "pick_clock_seconds" => clock,
            "draft_starts_at" => DateTime.utc_now() |> DateTime.add(15 * 60, :second) |> DateTime.to_iso8601()
          }
          |> put_who(rivals)
          |> put_slate(socket.assigns.slate_kind, socket.assigns.slate)

        submit(socket, attrs)
    end
  end

  # Tampered or unknown events must not crash the socket.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp put_who(attrs, [single]), do: Map.put(attrs, "opponent_id", single)
  defp put_who(attrs, many), do: Map.put(attrs, "opponent_ids", many)

  defp put_slate(attrs, _kind, nil), do: attrs
  defp put_slate(attrs, "week", id), do: Map.put(attrs, "slate_week", id)
  defp put_slate(attrs, "day", id), do: Map.put(attrs, "slate_date", id)

  defp submit(%{assigns: %{counter: %{} = original}} = socket, attrs) do
    case Contests.counter_challenge(socket.assigns.current_user, original.id, attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Counter sent — their move now.") |> push_navigate(to: "/app/duels")}

      {:error, reason} ->
        {:noreply, assign(socket, error: humanize(reason))}
    end
  end

  defp submit(socket, attrs) do
    case Contests.create_challenge(socket.assigns.current_user, attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Challenge sent.") |> push_navigate(to: "/app/duels")}

      {:error, reason} ->
        {:noreply, assign(socket, error: humanize(reason))}
    end
  end

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(%Ecto.Changeset{}), do: "Those terms don't work — check them and try again."
  defp humanize(reason), do: "Couldn't send it (#{inspect(reason)})."

  # --- render (the design's markup) -------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-wrap:wrap;gap:24px;max-width:1080px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="flex:1;min-width:min(440px,100%);display:flex;flex-direction:column;gap:18px">
          <div style="display:flex;flex-direction:column">
            <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">
              {if @counter, do: "COUNTER OFFER", else: "NEW CHALLENGE"}
            </span>
            <span style="font-size:11.5px;color:#8B91A7;font-weight:600">
              Set the terms first, then pick who has to answer for it.
            </span>
            <div :if={@counter} style="margin-top:10px;display:flex;align-items:center;gap:8px;background:rgba(124,92,255,.12);border:1px solid #7C5CFF;border-radius:11px;padding:9px 14px">
              <span style="font-size:11px;font-weight:900;letter-spacing:1px;color:#A794FF">COUNTER OFFER</span>
              <span style="font-size:11.5px;color:#C7CBD9;font-weight:600">
                You're editing {@counter.challenger.username}'s terms — sending returns it to them to accept or decline.
              </span>
            </div>
            <p :if={@error} style="margin-top:10px;font-size:12px;font-weight:700;color:#FF4557">{@error}</p>
          </div>

          <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;padding:18px;display:flex;flex-direction:column;gap:16px">
            <div style="display:flex;flex-direction:column;gap:8px">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">LEAGUE</span>
              <div style="display:flex;gap:8px;flex-wrap:wrap">
                <button
                  :for={l <- @leagues}
                  phx-click="league"
                  phx-value-key={l.key}
                  disabled={not MapSet.member?(@playable, l.key)}
                  class="hu-cond"
                  style={pill(@league == l.key, 16) <> if(MapSet.member?(@playable, l.key), do: "", else: ";opacity:.3;cursor:not-allowed")}
                >
                  {l.label}{if not MapSet.member?(@playable, l.key), do: " · OFF-SEASON"}
                </button>
              </div>
            </div>

            <div style="display:flex;flex-direction:column;gap:8px">
              <div style="display:flex;align-items:center;gap:8px">
                <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">ROSTER SIZE</span>
                <button
                  phx-click="shapes-toggle"
                  class="hover:text-[#C8FF2E]"
                  style={"cursor:pointer;background:transparent;border:1px solid #{if @shapes_open, do: "rgba(200,255,46,.45)", else: "#252A3A"};color:#{if @shapes_open, do: "var(--acc,#C8FF2E)", else: "#8B91A7"};font-size:9.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:3px 10px"}
                >
                  ⓘ SHAPES
                </button>
              </div>
              <div style="display:flex;gap:8px">
                <button
                  :for={n <- @rosters}
                  phx-click="roster"
                  phx-value-n={n}
                  disabled={not roster_ok?(assigns, n)}
                  title={if not roster_ok?(assigns, n), do: "This slate can't feed a #{n}-slot draft"}
                  class="hu-cond"
                  style={pill(@roster == n, 16) <> if(roster_ok?(assigns, n), do: "", else: ";opacity:.3;cursor:not-allowed")}
                >
                  {n} SLOTS
                </button>
              </div>
              <div :if={@shapes_open} style="display:flex;flex-direction:column;gap:6px;border:1px solid #252A3A;background:#0D0F16;border-radius:12px;padding:11px 14px">
                <div :for={n <- @rosters} style="display:flex;align-items:baseline;gap:10px">
                  <span class="hu-cond" style={"font-size:15px;flex:none;width:64px;color:#{if @roster == n, do: "var(--acc,#C8FF2E)", else: "#B9BECF"}"}>
                    {n} SLOTS
                  </span>
                  <span style="font-size:11px;font-weight:700;color:#8B91A7">{shape_line(@league, n)}</span>
                </div>
                <span style="font-size:10px;color:#565D73;font-weight:600">Positions lock as you draft — the board only offers players who still fit your open slots.</span>
              </div>
            </div>

            <div style="display:flex;flex-direction:column;gap:8px">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">PICK CLOCK</span>
              <div style="display:flex;gap:8px">
                <button :for={n <- @clocks} phx-click="clock" phx-value-n={n} style={pill(@clock == n, 12)}>
                  {n} sec
                </button>
              </div>
            </div>

            <div :if={@slates != []} style="display:flex;flex-direction:column;gap:8px">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">SLATE</span>
              <div style="display:flex;gap:8px;flex-wrap:wrap">
                <button
                  :for={s <- @slates}
                  phx-click="slate"
                  phx-value-id={slate_id(@slate_kind, s)}
                  style={pill(@slate == slate_id(@slate_kind, s), 12)}
                >
                  {slate_label(@slate_kind, s)} · {s.upcoming}
                </button>
              </div>
            </div>
          </div>

          <div :if={!@counter} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
            <div style="padding:13px 18px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">WHO ANSWERS FOR IT</span>
              <span style={"font-size:11px;font-weight:800;color:#{if length(@rivals) >= @max_rivals, do: "#FFB021", else: "#565D73"}"}>
                {length(@rivals)}/{@max_rivals} CALLED OUT
              </span>
            </div>
            <div :if={@groups != []} style="padding:12px 18px 0;display:flex;gap:7px;flex-wrap:wrap">
              <button
                :for={g <- [%{name: "ALL"} | @groups]}
                phx-click="group"
                phx-value-g={g.name}
                style={group_pill(@group_tab == g.name)}
              >
                {String.upcase(g.name)}
              </button>
            </div>
            <p :if={@friends == []} style="padding:16px 18px;font-size:12px;color:#565D73;font-weight:600">
              No friends yet — add some from your profile first.
            </p>
            <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px;padding:14px 18px 18px">
              <div
                :for={f <- visible_friends(@friends, @groups, @group_tab)}
                phx-click="rival"
                phx-value-id={f.id}
                style={"cursor:pointer;display:flex;align-items:center;gap:10px;border:1px solid #{if f.id in @rivals, do: "var(--acc,#C8FF2E)", else: "#252A3A"};background:#{if f.id in @rivals, do: "rgba(200,255,46,.07)", else: "transparent"};border-radius:12px;padding:10px 12px"}
              >
                <div style={"width:32px;height:32px;flex:none;border-radius:10px;background:#{if f.id in @rivals, do: "rgba(200,255,46,.15)", else: "rgba(124,92,255,.15)"};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:12px;color:#{if f.id in @rivals, do: "#C8FF2E", else: "#9F8BFF"}"}>
                  {f.username |> String.slice(0, 2) |> String.upcase()}
                </div>
                <div style="display:flex;flex-direction:column;min-width:0">
                  <span style="font-weight:800;font-size:12.5px">{f.username}</span>
                  <span style="font-size:10px;color:#565D73;font-weight:700">
                    {Map.get(@rec_by_id, f.id, "no duels yet")}
                  </span>
                </div>
                <span style={"margin-left:auto;width:16px;height:16px;flex:none;border-radius:9px;border:1px solid #{if f.id in @rivals, do: "var(--acc,#C8FF2E)", else: "#3A4157"};background:#{if f.id in @rivals, do: "var(--acc,#C8FF2E)", else: "transparent"}"}>
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- THE TERMS rail --%>
        <div style="width:300px;flex:none;display:flex;flex-direction:column;gap:14px;position:sticky;top:70px;align-self:flex-start">
          <div style="border-radius:16px;border:1px solid color-mix(in srgb,var(--acc,#C8FF2E) 35%,transparent);background:linear-gradient(150deg,color-mix(in srgb,var(--acc,#C8FF2E) 9%,#12141D),#12141D 60%);padding:18px;display:flex;flex-direction:column;gap:12px">
            <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:var(--acc,#C8FF2E)">THE TERMS</span>
            <div class="hu-cond" style="font-size:28px;line-height:1.05">{terms_headline(assigns)}</div>
            <div style="display:flex;flex-direction:column;gap:7px">
              <.term_row label="Slate" value={selected_slate_label(assigns)} />
              <.term_row label="Pick clock" value={"#{@clock} sec"} />
              <.term_row label="Called out" value={rivals_summary(assigns)} />
            </div>
            <button
              phx-click="send"
              class="hu-cond"
              style={"cursor:pointer;background:#{if @rivals == [], do: "#252A3A", else: "var(--acc,#C8FF2E)"};color:#{if @rivals == [], do: "#565D73", else: "#0A0B10"};border-radius:12px;padding:13px;text-align:center;font-size:18px;letter-spacing:.5px;border:none;width:100%"}
            >
              {if @counter, do: "SEND THE COUNTER →", else: "SEND IT →"}
            </button>
            <span style="font-size:10.5px;color:#565D73;font-weight:600;text-align:center">
              Everyone you call out gets a seat when they accept. Max 5 drafters.
            </span>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp term_row(assigns) do
    ~H"""
    <div style="display:flex;justify-content:space-between">
      <span style="font-size:11.5px;color:#8B91A7;font-weight:700">{@label}</span>
      <span style="font-size:11.5px;font-weight:800">{@value}</span>
    </div>
    """
  end

  # --- design tokens ----------------------------------------------------------

  # "2 GUARD · 2 FORWARD · FLEX" — read straight off the real template so the
  # info panel can never drift from what the draft actually deals.
  defp shape_line(league, n) do
    "#{league}_#{n}"
    |> Lineup.slots()
    |> Enum.map(& &1.label)
    |> Enum.chunk_by(& &1)
    |> Enum.map_join(" · ", fn
      [label] -> label
      [label | _] = run -> "#{length(run)} #{label}"
    end)
  end

  defp pill(true, font),
    do:
      "cursor:pointer;border:1px solid var(--acc,#C8FF2E);background:rgba(200,255,46,.1);color:var(--acc,#C8FF2E);font-size:#{font}px;font-weight:800;border-radius:999px;padding:9px 20px;white-space:nowrap"

  defp pill(false, font),
    do:
      "cursor:pointer;border:1px solid #252A3A;background:transparent;color:#B9BECF;font-size:#{font}px;font-weight:800;border-radius:999px;padding:9px 20px;white-space:nowrap"

  defp group_pill(true),
    do:
      "cursor:pointer;font-size:11px;font-weight:800;letter-spacing:.5px;color:#0A0B10;background:var(--acc,#C8FF2E);border:1px solid var(--acc,#C8FF2E);border-radius:999px;padding:6px 14px"

  defp group_pill(false),
    do:
      "cursor:pointer;font-size:11px;font-weight:800;letter-spacing:.5px;color:#8B91A7;background:transparent;border:1px solid #252A3A;border-radius:999px;padding:6px 14px"

  # The server rejects a slate that can't field roster x drafters x 2 bodies.
  # Mirror it here (the phone does the same) so sizes grey out BEFORE you send.
  defp fits?(assigns, size, drafters) do
    case slate_players(assigns) do
      nil -> true
      players -> players >= size * drafters * 2
    end
  end

  defp roster_ok?(assigns, size), do: fits?(assigns, size, max(length(assigns.rivals) + 1, 2))

  defp slate_players(%{slate: nil}), do: nil

  defp slate_players(%{slates: slates, slate_kind: kind, slate: id}) do
    case Enum.find(slates, &(slate_id(kind, &1) == id)) do
      %{players: players} -> players
      _ -> nil
    end
  end

  # If the picked roster stops fitting (slate changed, or a rival joined),
  # fall back to the largest size that still works.
  defp resnap_roster(socket) do
    %{roster: roster, rosters: rosters} = socket.assigns

    if roster_ok?(socket.assigns, roster) do
      socket
    else
      case rosters |> Enum.reverse() |> Enum.find(&roster_ok?(socket.assigns, &1)) do
        nil -> socket
        ok -> assign(socket, roster: ok)
      end
    end
  end

  defp visible_friends(friends, _groups, "ALL"), do: friends

  defp visible_friends(friends, groups, tab) do
    case Enum.find(groups, &(&1.name == tab)) do
      nil -> friends
      g -> Enum.filter(friends, &(&1.id in g.member_ids))
    end
  end

  defp terms_headline(%{league: league, roster: roster}) do
    "#{String.upcase(league)} · #{roster} SLOTS · SNAKE"
  end

  defp rivals_summary(%{counter: %{} = c}), do: c.challenger.username
  defp rivals_summary(%{rivals: []}), do: "nobody yet"

  defp rivals_summary(%{rivals: rivals, friends: friends}) do
    names = friends |> Enum.filter(&(&1.id in rivals)) |> Enum.map(& &1.username)

    case names do
      [one] -> one
      [a, b] -> "#{a} + #{b}"
      many -> "#{length(many)} rivals"
    end
  end

  defp selected_slate_label(%{slate: nil}), do: "Auto"

  defp selected_slate_label(%{slate: id, slate_kind: kind, slates: slates}) do
    case Enum.find(slates, &(slate_id(kind, &1) == id)) do
      nil -> "Auto"
      s -> slate_label(kind, s)
    end
  end

  defp slate_label("week", w), do: w.label

  defp slate_label("day", d) do
    today = Slate.today()

    cond do
      d.date == today -> "Tonight"
      d.date == Date.add(today, 1) -> "Tomorrow"
      true -> Calendar.strftime(d.date, "%a %b %-d")
    end
  end
end
