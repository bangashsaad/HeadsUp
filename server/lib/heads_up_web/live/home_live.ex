defmodule HeadsUpWeb.HomeLive do
  @moduledoc """
  Home, wearing the design's exact markup: the season-record hero, the YOUR
  MOVE cards, the rivalries row, and the live-duel + slate pair. The DOM and
  inline styles come from the Claude Design export; only the demo data was
  replaced with the real thing.

  The live-duel card's scores need ESPN, so they load after first paint —
  mount stays instant and the card fills in when the numbers arrive.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUpWeb.Params

  alias HeadsUp.{Coins, Home, Settlement, Stats}
  alias HeadsUp.Sports.Schedule

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    summary = Home.summary(user)

    live_duel = List.first(summary.awaiting)

    if connected?(socket) do
      HeadsUpWeb.Endpoint.subscribe(HeadsUp.Contests.Events.topic(user.id))
      if live_duel, do: send(self(), {:load_live_card, live_duel.id})
      send(self(), :load_slate)
    end

    {:ok,
     socket
     |> assign(page_title: "Home")
     |> assign(
       summary: summary,
       record: Stats.record_for(user.id),
       h2h: Stats.head_to_head(user.id) |> Enum.take(3),
       coins: Coins.balance(user.id),
       live_duel: live_duel,
       live_card: nil,
       slate: []
     )}
  end

  @impl true
  def handle_info({:load_live_card, duel_id}, socket) do
    card =
      case Settlement.live_result(duel_id) do
        {:ok, live} ->
          rendered = HeadsUpWeb.LiveJSON.show(%{live: live, current_user_id: socket.assigns.current_user.id})
          # In a 3-4 player duel the viewer can rank below the top two — the
          # card must still show THEIR score under YOU, vs the best other.
          me = Enum.find(rendered.sides, & &1.is_me)
          best_other = rendered.sides |> Enum.reject(& &1.is_me) |> List.first()
          %{a: me || List.first(rendered.sides), b: best_other, games: rendered.games}

        _ ->
          nil
      end

    {:noreply, assign(socket, live_card: card)}
  end

  def handle_info(:load_slate, socket) do
    games =
      ~w(wnba mlb nfl)
      |> Enum.flat_map(fn sport ->
        case Schedule.upcoming(sport) do
          {:ok, list} -> Enum.take(list, 3)
          _ -> []
        end
      end)
      |> Enum.take(6)

    {:noreply, assign(socket, slate: games)}
  end

  # Something on the board moved — recompute the dashboard's duel-shaped bits.
  def handle_info(%Phoenix.Socket.Broadcast{event: "duel_changed"}, socket) do
    user = socket.assigns.current_user
    summary = Home.summary(user)
    live_duel = List.first(summary.awaiting)
    if live_duel, do: send(self(), {:load_live_card, live_duel.id})

    {:noreply,
     assign(socket,
       summary: summary,
       record: Stats.record_for(user.id),
       h2h: Stats.head_to_head(user.id) |> Enum.take(3),
       coins: Coins.balance(user.id),
       live_duel: live_duel,
       live_card: if(live_duel, do: socket.assigns.live_card)
     )}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("accept", %{"id" => id}, socket) do
    if not HeadsUpWeb.UserAuth.verified_for_duels?(socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:error, "Verify your email to duel — takes a few seconds.")
       |> push_navigate(to: "/app/verify")}
    else
      do_accept(socket, id)
    end
  end

  defp do_accept(socket, id) do
    case HeadsUp.Contests.accept_challenge(socket.assigns.current_user, Params.int(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Locked in. Draft time.")
         |> assign(summary: Home.summary(socket.assigns.current_user))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("decline", %{"id" => id}, socket) do
    case HeadsUp.Contests.decline_challenge(socket.assigns.current_user, Params.int(id)) do
      {:ok, _} ->
        {:noreply, assign(socket, summary: Home.summary(socket.assigns.current_user))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  # Tampered or unknown events must not crash the socket.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: "Couldn't do that (#{inspect(reason)})."

  # --- render (the design's markup, verbatim) --------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:20px;max-width:920px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;flex-direction:column;gap:20px">
          <%!-- season record hero --%>
          <div style="display:flex;align-items:flex-end;justify-content:space-between;background:radial-gradient(560px 260px at 12% 0%,rgba(124,92,255,.18),transparent 65%);border-radius:18px;padding:4px 4px 0">
            <div style="display:flex;flex-direction:column">
              <span style="font-size:11px;font-weight:800;letter-spacing:2.5px;color:#565D73">SEASON RECORD</span>
              <span class="hu-cond" style="font-size:70px;line-height:.95">{@record.wins}<span style="color:#565D73">–</span>{@record.losses}</span>
            </div>
            <div style="display:flex;flex-direction:column;gap:8px;padding-bottom:10px;align-items:flex-end">
              <div style="display:flex;gap:5px">
                <span
                  :for={r <- Enum.take(@record.recent || [], 5)}
                  style={"width:22px;height:22px;border-radius:7px;background:#{chip_bg(r)};border:1px solid #{chip_ink(r)};color:#{chip_ink(r)};font-size:11px;font-weight:900;display:flex;align-items:center;justify-content:center"}
                >
                  {r}
                </span>
              </div>
              <span style="font-size:12px;font-weight:700;color:#8B91A7">
                {win_pct(@record)}% WIN{streak_label(@record)}
              </span>
            </div>
          </div>

          <div style="display:flex;align-items:baseline;justify-content:space-between">
            <span class="hu-cond" style="font-size:19px;letter-spacing:1px">YOUR MOVE</span>
            <span style="font-size:11px;font-weight:800;letter-spacing:1px;color:#565D73">{pending_label(@summary)}</span>
          </div>

          <%!-- his empty state: nobody owes you a move --%>
          <div
            :if={@summary.draft_ready == [] and @summary.needs_response == [] and @summary.waiting_on_them == []}
            style="position:relative;overflow:hidden;border-radius:18px;border:1px dashed #3A4157;padding:28px 24px;display:flex;align-items:center;gap:24px;flex-wrap:wrap"
          >
            <div style="position:absolute;right:-10px;top:-34px;font-family:'Archivo Black',sans-serif;font-style:italic;font-size:130px;color:transparent;-webkit-text-stroke:1px rgba(244,245,247,.06);pointer-events:none">
              VS
            </div>
            <div style="display:flex;flex-direction:column;gap:6px;flex:1;min-width:240px">
              <span class="hu-cond" style="font-size:34px;line-height:1">ALL QUIET. TOO QUIET<span style="color:var(--acc,#C8FF2E)">.</span></span>
              <span style="font-size:13px;color:#8B91A7;font-weight:600">Nobody owes you a move — go make someone answer for it.</span>
            </div>
            <.link
              navigate={~p"/app/new"}
              class="hu-cond huw-pulse"
              style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:18px;letter-spacing:.5px;border-radius:999px;padding:13px 28px;white-space:nowrap"
            >
              CALL SOMEONE OUT →
            </.link>
          </div>

          <%!-- the hero card: your live draft, or the one that's set --%>
          <.link
            :for={duel <- Enum.take(@summary.draft_ready, 1)}
            navigate={~p"/app/draft/#{duel.id}"}
            style="cursor:pointer;position:relative;overflow:hidden;border-radius:18px;border:1px solid color-mix(in srgb,var(--acc,#C8FF2E) 45%,transparent);background:linear-gradient(120deg,color-mix(in srgb,var(--acc,#C8FF2E) 15%,#12141D),#12141D 55%,rgba(124,92,255,.14));padding:20px 24px;display:block"
          >
            <div style="position:absolute;right:-10px;top:-30px;font-family:'Archivo Black',sans-serif;font-style:italic;font-size:120px;color:transparent;-webkit-text-stroke:1px rgba(244,245,247,.09);pointer-events:none">
              VS
            </div>
            <div style="display:flex;align-items:center;justify-content:space-between">
              <span style="display:inline-flex;align-items:center;gap:7px;background:rgba(255,69,87,.15);border:1px solid #FF4557;border-radius:999px;padding:4px 11px">
                <span class="huw-blink" style="width:6px;height:6px;border-radius:3px;background:#FF4557"></span>
                <span style="color:#FF4557;font-size:11px;font-weight:900;letter-spacing:1.5px">
                  {if duel.status == "drafting", do: "DRAFT LIVE", else: "DRAFT SET"}
                </span>
              </span>
              <span style="font-size:11px;font-weight:800;color:#8B91A7;letter-spacing:1px">
                {String.upcase(duel.sport)} · {duel.roster_size} SLOTS · SNAKE
              </span>
            </div>
            <div class="hu-cond" style="font-size:38px;line-height:1;margin-top:15px">
              {hero_line(duel, @current_user.id)}<span style="color:var(--acc,#C8FF2E)">.</span>
            </div>
            <div style="display:flex;align-items:center;justify-content:space-between;margin-top:15px">
              <span style="font-size:13px;color:#8B91A7;font-weight:600">Winner takes the rivalry lead</span>
              <span class="hu-cond" style="background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:10px 22px;white-space:nowrap">
                ENTER ROOM →
              </span>
            </div>
          </.link>

          <%!-- challenge + ready cards --%>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px">
            <div
              :for={duel <- Enum.take(@summary.needs_response, 2)}
              style="border-radius:16px;border:1px solid #252A3A;background:#12141D;padding:17px;display:flex;flex-direction:column"
            >
              <div style="display:flex;align-items:center;justify-content:space-between">
                <span style="font-size:11px;font-weight:900;letter-spacing:1.2px;color:#7C5CFF">CHALLENGE</span>
                <span class="huw-blink" style="width:8px;height:8px;border-radius:4px;background:#7C5CFF"></span>
              </div>
              <div style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:23px;margin-top:8px;line-height:1.05">
                {other_name(duel, @current_user.id)} called you out
              </div>
              <div style="font-size:12px;color:#8B91A7;margin-top:6px;font-weight:600">{meta_line(duel)}</div>
              <div style="display:flex;gap:8px;margin-top:13px">
                <button
                  phx-click="accept"
                  phx-value-id={duel.id}
                  class="hu-cond"
                  style="cursor:pointer;flex:1;text-align:center;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:15px;border-radius:999px;padding:8px 0;border:none"
                >
                  ACCEPT
                </button>
                <button
                  phx-click="decline"
                  phx-value-id={duel.id}
                  class="hu-cond"
                  style="cursor:pointer;flex:1;text-align:center;border:1px solid #252A3A;color:#8B91A7;font-size:15px;border-radius:999px;padding:8px 0;background:transparent"
                >
                  DECLINE
                </button>
              </div>
            </div>

            <div
              :for={duel <- Enum.drop(@summary.draft_ready, 1) |> Enum.take(2 - min(length(@summary.needs_response), 2))}
              style="border-radius:16px;border:1px solid #252A3A;background:#12141D;padding:17px;display:flex;flex-direction:column"
            >
              <div style="display:flex;align-items:center;justify-content:space-between">
                <span style="font-size:11px;font-weight:900;letter-spacing:1.2px;color:var(--acc,#C8FF2E)">READY</span>
                <span style="display:inline-block;width:13px;height:13px;background:var(--acc,#C8FF2E);-webkit-mask:url('/icons/d986b787.svg') center/contain no-repeat;mask:url('/icons/d986b787.svg') center/contain no-repeat">
                </span>
              </div>
              <div style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:23px;margin-top:8px;line-height:1.05">
                Draft vs {other_name(duel, @current_user.id)} anytime
              </div>
              <div style="font-size:12px;color:#8B91A7;margin-top:6px;font-weight:600">{meta_line(duel)}</div>
              <.link
                navigate={~p"/app/draft/#{duel.id}"}
                class="hu-cond"
                style="cursor:pointer;margin-top:13px;align-self:flex-start;border:1px solid var(--acc,#C8FF2E);color:var(--acc,#C8FF2E);font-size:15px;border-radius:999px;padding:8px 20px"
              >
                START DRAFT →
              </.link>
            </div>
          </div>

          <%!-- rivalries --%>
          <div style="display:flex;align-items:baseline;justify-content:space-between;margin-top:4px">
            <span class="hu-cond" style="font-size:19px;letter-spacing:1px">RIVALRIES</span>
            <.link navigate={~p"/app/you"} style="cursor:pointer;font-size:11px;font-weight:800;letter-spacing:1px;color:var(--acc,#C8FF2E)">
              ALL RIVALS →
            </.link>
          </div>
          <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:14px">
            <div
              :for={rv <- @h2h}
              style="border-radius:16px;border:1px solid #252A3A;background:#12141D;padding:15px;display:flex;flex-direction:column;gap:10px"
            >
              <div style="display:flex;align-items:center;gap:10px">
                <div style={"width:34px;height:34px;flex:none;border-radius:10px;background:#{rival_bg(rv)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;color:#{rival_ink(rv)}"}>
                  {initials(rv.opponent.username)}
                </div>
                <div style="display:flex;flex-direction:column;min-width:0">
                  <span style="font-weight:800;font-size:13px">{rv.opponent.username}</span>
                  <span style="font-size:10.5px;color:#565D73;font-weight:700">{rv.played} duels</span>
                </div>
              </div>
              <div style="display:flex;align-items:baseline;gap:7px">
                <span class="hu-cond" style={"font-size:28px;color:#{rival_ink(rv)}"}>{rv.wins}–{rv.losses}</span>
                <span style="font-size:10.5px;font-weight:800;letter-spacing:1px;color:#565D73">{rival_tag(rv)}</span>
              </div>
            </div>
            <p :if={@h2h == []} style="grid-column:1/-1;font-size:12px;color:#565D73;font-weight:600">
              Finish a duel and the rivalry ledger starts.
            </p>
          </div>
        </div>

        <%!-- live duel + slate --%>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:14px;align-items:start">
          <div :if={@live_duel} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
            <.link
              navigate={~p"/app/live/#{@live_duel.id}"}
              style="cursor:pointer;padding:13px 16px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between"
            >
              <span class="hu-cond" style="font-size:15px;letter-spacing:1px">
                LIVE DUEL · {String.upcase(other_name(@live_duel, @current_user.id))}
              </span>
              <span style="display:inline-flex;align-items:center;gap:5px">
                <span class="huw-blink" style="width:6px;height:6px;border-radius:3px;background:#FF4557"></span>
                <span style="color:#FF4557;font-size:10px;font-weight:900">LIVE</span>
              </span>
            </.link>
            <div style="padding:14px 16px;display:flex;align-items:center;justify-content:space-between">
              <div style="display:flex;flex-direction:column;align-items:center;gap:2px">
                <span style="font-size:10px;font-weight:900;letter-spacing:1px;color:var(--acc,#C8FF2E)">YOU</span>
                <span class="hu-cond" style="font-size:40px;line-height:1">{card_total(@live_card, :me)}</span>
              </div>
              <span class="hu-black" style="font-size:15px;color:#565D73">VS</span>
              <div style="display:flex;flex-direction:column;align-items:center;gap:2px">
                <span style="font-size:10px;font-weight:900;letter-spacing:1px;color:#8B91A7">
                  {String.upcase(other_name(@live_duel, @current_user.id))}
                </span>
                <span class="hu-cond" style="font-size:40px;line-height:1;color:#8B91A7">{card_total(@live_card, :them)}</span>
              </div>
            </div>
            <div style="padding:0 16px 15px">
              <div style="height:7px;border-radius:4px;background:#252A3A;overflow:hidden">
                <div style={"width:#{card_pct(@live_card)}%;height:100%;background:var(--acc,#C8FF2E)"}></div>
              </div>
              <div style="display:flex;justify-content:space-between;margin-top:8px">
                <span style="font-size:11px;font-weight:700;color:#8B91A7">{card_games(@live_card)}</span>
                <.link navigate={~p"/app/live/#{@live_duel.id}"} style="cursor:pointer;font-size:11px;font-weight:900;letter-spacing:1px;color:var(--acc,#C8FF2E)">
                  WATCH →
                </.link>
              </div>
            </div>
          </div>

          <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
            <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between">
              <span class="hu-cond" style="font-size:15px;letter-spacing:1px">TONIGHT'S SLATE</span>
              <span style="font-size:10px;font-weight:800;letter-spacing:1px;color:#565D73">WNBA + MLB + NFL</span>
            </div>
            <div :for={g <- @slate} style="display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid #14171F">
              <img :if={g.away && g.away.logo} src={g.away.logo} style="width:24px;height:24px;object-fit:contain" alt="" loading="lazy" />
              <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:15px;width:86px">
                {g.away && g.away.abbrev} @ {g.home && g.home.abbrev}
              </span>
              <img :if={g.home && g.home.logo} src={g.home.logo} style="width:24px;height:24px;object-fit:contain" alt="" loading="lazy" />
              <span style={"margin-left:auto;font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:13px;color:#{game_color(g)}"}>
                {game_meta(g)}
              </span>
            </div>
            <p :if={@slate == []} style="padding:14px 16px;font-size:12px;color:#565D73;font-weight:600">
              Quiet night — no games on the slate.
            </p>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  # --- data helpers ----------------------------------------------------------

  defp chip_bg("W"), do: "rgba(200,255,46,.12)"
  defp chip_bg("L"), do: "rgba(255,69,87,.10)"
  defp chip_bg(_), do: "rgba(139,145,167,.10)"

  defp chip_ink("W"), do: "#C8FF2E"
  defp chip_ink("L"), do: "#FF4557"
  defp chip_ink(_), do: "#8B91A7"

  defp win_pct(%{wins: w, losses: l}) when w + l > 0, do: round(w / (w + l) * 100)
  defp win_pct(_), do: 0

  defp streak_label(%{streak: %{count: c, type: "win"}}) when c > 1, do: " · 🔥 W#{c} STREAK"
  defp streak_label(%{streak: %{count: c, type: "loss"}}) when c > 1, do: " · L#{c} STREAK"

  defp streak_label(_), do: ""

  defp pending_label(summary) do
    case length(summary.needs_response) do
      0 -> "ALL QUIET"
      n -> "#{n} PENDING"
    end
  end

  defp hero_line(duel, me) do
    name = duel |> other_name(me) |> String.upcase()
    if duel.status == "drafting", do: "THE DRAFT IS LIVE VS #{name}", else: "DRAFT VS #{name} IS SET"
  end

  defp other_name(duel, me) do
    cond do
      duel.opponent_id == nil ->
        host = Enum.find(duel.participants || [], &(&1.seat == 0))
        n = length(duel.participants || [])
        if host && host.user_id != me, do: host.user.username, else: "the #{n}-player table"

      duel.challenger_id == me ->
        (duel.opponent && duel.opponent.username) || "them"

      true ->
        (duel.challenger && duel.challenger.username) || "them"
    end
  end

  defp meta_line(duel) do
    sport = sport_emoji(duel.sport) <> " " <> String.upcase(duel.sport)

    stake =
      if duel.stake_coins > 0,
        do: " · ◎ #{duel.stake_coins} stake · ◎ #{duel.stake_coins * 2} pot",
        else: " · no stake"

    "#{sport} · #{duel.roster_size} slots#{stake}"
  end

  defp sport_emoji("mlb"), do: "⚾️"
  defp sport_emoji("nfl"), do: "🏈"
  defp sport_emoji(_), do: "🏀"

  defp rival_bg(rv), do: if(rv.wins >= rv.losses, do: "rgba(200,255,46,.12)", else: "rgba(124,92,255,.15)")
  defp rival_ink(rv), do: if(rv.wins >= rv.losses, do: "#C8FF2E", else: "#9F8BFF")
  defp rival_tag(rv), do: if(rv.wins >= rv.losses, do: "YOU LEAD", else: "THEY LEAD")

  defp initials(name) do
    name |> String.slice(0, 2) |> String.upcase()
  end

  defp card_total(nil, _), do: "—"
  defp card_total(%{a: a, b: b}, :me), do: fmt_total(if(a.is_me, do: a, else: b))
  defp card_total(%{a: a, b: b}, :them), do: fmt_total(if(a.is_me, do: b, else: a))

  defp fmt_total(nil), do: "—"
  defp fmt_total(%{total: t}) when is_float(t), do: :erlang.float_to_binary(t, decimals: 1)
  defp fmt_total(%{total: t}), do: to_string(t)

  defp card_pct(nil), do: 50

  defp card_pct(%{a: a, b: b}) do
    {me, them} = if a.is_me, do: {a, b}, else: {b, a}
    total = (me.total || 0) + (them.total || 0)
    if total > 0, do: round((me.total || 0) / total * 100), else: 50
  end

  defp card_games(nil), do: "scores loading…"

  defp card_games(%{games: %{final: f, live: l, upcoming: u}}),
    do: "#{f} FINAL · #{l} LIVE · #{u} TO TIP"

  defp card_games(_), do: ""

  defp game_color(%{state: "in"}), do: "#FF4557"
  defp game_color(%{state: "post"}), do: "#8B91A7"
  defp game_color(_), do: "#565D73"

  defp game_meta(%{state: "in"} = g), do: g.status || "LIVE"
  defp game_meta(%{state: "post"}), do: "FINAL"
  defp game_meta(g), do: g.status || ""
end
