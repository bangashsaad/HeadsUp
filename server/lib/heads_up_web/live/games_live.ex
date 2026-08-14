defmodule HeadsUpWeb.GamesLive do
  @moduledoc """
  The scoreboard in the design's clothes: big tinted game cards with team
  logos and drop shadows for live games, compact rows for scheduled and final
  ones, section rules between the states, plus the player-pool browse. Data
  is the same `Sports.Schedule` the phone reads.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Sports.Schedule

  @sports ~w(wnba mlb nfl)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Scoreboard", sport: "wnba", sports_list: @sports)
     |> load()}
  end

  defp load(%{assigns: %{sport: sport}} = socket) do
    games =
      case Schedule.upcoming(sport) do
        {:ok, list} -> list
        _ -> []
      end

    assign(socket,
      live_games: Enum.filter(games, &(&1.state == "in")),
      pre_games: Enum.filter(games, &(&1.state == "pre")),
      post_games: Enum.filter(games, &(&1.state == "post"))
    )
  end

  @impl true
  def handle_event("sport", %{"key" => key}, socket) when key in @sports do
    {:noreply, socket |> assign(sport: key) |> load()}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # --- render (the design's markup) -------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:12px;max-width:780px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap">
          <div style="display:flex;flex-direction:column">
            <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">SCOREBOARD</span>
            <span style="font-size:11.5px;color:#8B91A7;font-weight:600">Real games, live box scores, fantasy leaders.</span>
          </div>
          <div style="display:flex;gap:6px">
            <button :for={s <- @sports_list} phx-click="sport" phx-value-key={s} class="hu-cond" style={league_pill(@sport == s)}>
              {String.upcase(s)}
            </button>
          </div>
        </div>

        <%= if true do %>
          <%!-- LIVE --%>
          <div :if={@live_games != []} style="display:flex;align-items:center;gap:6px;margin-top:8px">
            <span class="huw-blink" style="width:6px;height:6px;border-radius:3px;background:#FF4557"></span>
            <span style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#FF4557">LIVE NOW</span>
          </div>
          <div :for={g <- @live_games} style="position:relative;border-radius:18px;border:1px solid #252A3A;overflow:hidden;background:linear-gradient(120deg,rgba(124,92,255,.12),#12141D 50%,rgba(200,255,46,.06));padding:16px 14px 12px">
            <div style="display:flex;align-items:center;position:relative">
              <.team_col side={g.away} />
              <div style="flex:1;display:flex;align-items:center;justify-content:center;gap:14px">
                <span class="hu-cond" style="font-size:44px;line-height:1">{(g.away && g.away.score) || "0"}</span>
                <div style="display:flex;flex-direction:column;align-items:center;gap:3px;min-width:56px">
                  <div style="display:flex;align-items:center;gap:4px">
                    <span class="huw-blink" style="width:5px;height:5px;border-radius:3px;background:#FF4557"></span>
                    <span style="font-size:8px;font-weight:900;letter-spacing:1.5px;color:#FF4557">LIVE</span>
                  </div>
                  <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:12px;color:#8B91A7;text-align:center">
                    {g.status}
                  </span>
                </div>
                <span class="hu-cond" style="font-size:44px;line-height:1">{(g.home && g.home.score) || "0"}</span>
              </div>
              <.team_col side={g.home} />
            </div>
          </div>

          <%!-- SCHEDULE (the design's two-row card with the right rail) --%>
          <span :if={@pre_games != []} style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#565D73;margin-top:8px">SCHEDULE</span>
          <.game_card :for={g <- @pre_games} game={g} right={g.status} right_ink="var(--acc,#C8FF2E)" right_sub="START" dim={false} />

          <%!-- FINAL --%>
          <span :if={@post_games != []} style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#565D73;margin-top:8px">FINAL</span>
          <.game_card :for={g <- @post_games} game={g} right="FINAL" right_ink="#565D73" right_sub={nil} dim={true} />

          <div :if={@live_games == [] and @pre_games == [] and @post_games == []} style="padding:32px;text-align:center">
            <p class="hu-cond" style="font-size:22px;color:#8B91A7">QUIET NIGHT</p>
            <p style="font-size:12px;color:#565D73;font-weight:600">No games on that date — pick another day.</p>
          </div>
        <% end %>
      </div>
    </Layouts.shell>
    """
  end

  attr :game, :map, required: true
  attr :right, :string, required: true
  attr :right_ink, :string, required: true
  attr :right_sub, :string, default: nil
  attr :dim, :boolean, default: false

  defp game_card(assigns) do
    ~H"""
    <div style={"display:flex;border-radius:14px;border:1px solid #252A3A;overflow:hidden;background:linear-gradient(180deg,rgba(124,92,255,.07),#12141D 50%,rgba(200,255,46,.04))#{if @dim, do: ";opacity:.8"}"}>
      <div style="flex:1;display:flex;flex-direction:column;gap:8px;padding:11px 0 11px 12px">
        <.team_row side={@game.away} />
        <.team_row side={@game.home} />
      </div>
      <div style="width:70px;flex:none;border-left:1px solid #1A1E2B;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px">
        <span style={"font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:13px;letter-spacing:.5px;color:#{@right_ink};text-align:center"}>{@right}</span>
        <span :if={@right_sub} style="font-size:8.5px;font-weight:800;letter-spacing:.5px;color:#565D73">{@right_sub}</span>
      </div>
    </div>
    """
  end

  attr :side, :map, default: nil

  defp team_row(assigns) do
    ~H"""
    <div :if={@side} style="display:flex;align-items:center;gap:10px;padding-right:12px">
      <img :if={@side.logo} src={@side.logo} style="width:26px;height:26px;object-fit:contain" alt="" loading="lazy" />
      <span class="hu-black" style="font-size:14px;width:44px">{@side.abbrev}</span>
      <span style="flex:1;font-size:11.5px;font-weight:600;color:#8B91A7">{@side.name}</span>
      <span class="hu-cond" style="font-size:20px;color:#C7CBD9">{@side.score}</span>
    </div>
    """
  end

  attr :side, :map, default: nil

  defp team_col(assigns) do
    ~H"""
    <div :if={@side} style="width:90px;display:flex;flex-direction:column;align-items:center;gap:2px">
      <img :if={@side.logo} src={@side.logo} style="width:48px;height:48px;object-fit:contain" alt="" loading="lazy" />
      <span class="hu-black" style="font-size:16px;margin-top:4px">{@side.abbrev}</span>
      <span style="font-size:8.5px;font-weight:800;letter-spacing:1px;color:#8B91A7">{@side.name}</span>
    </div>
    """
  end

  defp league_pill(true),
    do:
      "cursor:pointer;border:1px solid var(--acc,#C8FF2E);background:rgba(200,255,46,.1);color:var(--acc,#C8FF2E);font-size:15px;border-radius:999px;padding:8px 18px;white-space:nowrap"

  defp league_pill(false),
    do:
      "cursor:pointer;border:1px solid #252A3A;background:transparent;color:#8B91A7;font-size:15px;border-radius:999px;padding:8px 18px;white-space:nowrap"

  defp day_pill(true),
    do:
      "cursor:pointer;border:1px solid var(--acc,#C8FF2E);background:var(--acc,#C8FF2E);color:#0A0B10;font-size:11px;font-weight:800;letter-spacing:.5px;border-radius:999px;padding:6px 14px;white-space:nowrap"

  defp day_pill(false),
    do:
      "cursor:pointer;border:1px solid #252A3A;background:transparent;color:#8B91A7;font-size:11px;font-weight:800;letter-spacing:.5px;border-radius:999px;padding:6px 14px;white-space:nowrap"

  defp proj(nil), do: "—"
  defp proj(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp proj(n), do: to_string(n)
end
