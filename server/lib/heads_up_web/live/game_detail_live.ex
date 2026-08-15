defmodule HeadsUpWeb.GameDetailLive do
  @moduledoc """
  One game, in the design's exact clothes — the screen behind every scoreboard
  card. Three states, mirroring the app's GameDetailScreen: upcoming shows the
  tip time, probable starters (baseball), team leaders (basketball) and SCOUT
  BOTH ROSTERS with projections; live and final show the line score, the
  fantasy heaters, and the full box score with a FAN column. Live games
  refresh every 30 seconds.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Sports
  alias HeadsUp.Sports.{BoxScore, Schedule}

  @tick_ms 30_000

  @impl true
  def mount(%{"id" => event_id} = params, _session, socket) do
    sport = params["sport"] || "wnba"

    case find_game(sport, event_id) do
      nil ->
        {:ok, socket |> put_flash(:error, "That game isn't on the board.") |> redirect(to: "/app/games")}

      game ->
        if connected?(socket) and game.state == "in" do
          :timer.send_interval(@tick_ms, self(), :tick)
        end

        {:ok,
         socket
         |> assign(page_title: "#{game.away && game.away.abbrev} @ #{game.home && game.home.abbrev}")
         |> assign(sport: sport, event_id: event_id)
         |> assign_game(game)}
    end
  end

  defp find_game(sport, event_id) do
    case Schedule.upcoming(sport) do
      {:ok, games} -> Enum.find(games, &(&1.id == event_id))
      _ -> nil
    end
  end

  defp assign_game(socket, game) do
    sport = socket.assigns.sport

    {box, linescores, heaters} =
      if game.state == "pre" do
        {nil, [], []}
      else
        case BoxScore.for_event(sport, game.id) do
          {:ok, box} -> {shape_box(box), linescore_cols(box), heaters(box)}
          _ -> {nil, [], []}
        end
      end

    socket
    |> assign(g: game, box: box, linescores: linescores, heaters: heaters)
    |> assign(kicker: "#{String.upcase(sport)} · REAL GAME")
    |> assign(rosters: if(game.state == "pre", do: roster_cards(sport, game), else: []))
  end

  @impl true
  def handle_info(:tick, socket) do
    case find_game(socket.assigns.sport, socket.assigns.event_id) do
      nil -> {:noreply, socket}
      game -> {:noreply, assign_game(socket, game)}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # --- data shaping -----------------------------------------------------------

  # The template binds t.head / g.label / r.fan — shape the box to those names.
  defp shape_box(box) do
    %{
      teams:
        Enum.map(box.teams, fn t ->
          %{
            logo: t.logo,
            head: "#{t.abbrev} BOX SCORE",
            groups:
              t.groups
              |> Enum.map(fn g ->
                %{
                  label: if(g.type not in [nil, ""], do: String.upcase(g.type)),
                  columns: g.columns,
                  rows: Enum.map(g.rows, fn r -> %{name: r.name, fan: r.fantasy, stats: r.stats} end)
                }
              end)
              |> Enum.reject(&(&1.rows == []))
          }
        end)
    }
  end

  # Per-period columns from the box score's team linescores.
  defp linescore_cols(box) do
    [a, b | _] = box.teams ++ [nil, nil]

    if a && b && a.linescores != [] do
      a.linescores
      |> Enum.zip(b.linescores ++ List.duplicate("", length(a.linescores)))
      |> Enum.with_index(1)
      |> Enum.map(fn {{av, hv}, i} -> %{label: period_label(i), a: av, h: hv} end)
    else
      []
    end
  end

  defp period_label(i), do: to_string(i)

  # Top fantasy performers across both teams — the design's heaters strip.
  defp heaters(box) do
    for team <- box.teams, group <- team.groups, row <- group.rows do
      %{
        name: row.name,
        team: team.abbrev,
        pts: row.fantasy,
        img: row[:headshot_url],
        line: Enum.join(Enum.take(row.stats, 3), " · ")
      }
    end
    |> Enum.sort_by(&(-(&1.pts || 0)))
    |> Enum.uniq_by(& &1.name)
    |> Enum.take(3)
  end

  # Pre-game: both teams' draftable players by projection.
  defp roster_cards(sport, game) do
    for side <- [game.away, game.home], side != nil do
      rows =
        sport
        |> Sports.list_players(team: side.abbrev, limit: 6)
        |> Enum.map(fn p ->
          %{name: p.name, pos: p.position, proj: proj(p.projection), img: headshot(p)}
        end)

      %{title: "#{side.abbrev} · TOP PROJECTED", rows: rows}
    end
  end

  defp headshot(p), do: HeadsUp.Sports.Headshot.for_player(p)

  defp proj(nil), do: "—"
  defp proj(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp proj(n), do: to_string(n)

  # Basketball pre-game leaders off the schedule feed (%{category, name, value}).
  defp leader_blocks(game) do
    for side <- [game.away, game.home],
        side != nil,
        is_list(side[:leaders]) and side[:leaders] != [] do
      %{
        team: side.abbrev,
        items:
          side.leaders
          |> Enum.take(3)
          |> Enum.map(fn l -> %{cat: l[:category], name: l[:name], val: l[:value]} end)
      }
    end
  end

  defp probable_line(nil), do: ""
  defp probable_line(p), do: p[:line] || p[:position] || ""

  defp initials(nil), do: "?"
  defp initials(name), do: name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join()

  defp start_label("mlb"), do: "FIRST PITCH · ET"
  defp start_label("nfl"), do: "KICKOFF · ET"
  defp start_label(_), do: "TIP-OFF · ET"

  defp start_word("mlb"), do: "first pitch"
  defp start_word("nfl"), do: "kickoff"
  defp start_word(_), do: "tip-off"

  # --- render (the design's markup, converted mechanically) -------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:14px;padding:28px 34px 50px;max-width:820px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
            <div style="display:flex;align-items:center;justify-content:space-between">
              <.link navigate={~p"/app/games"} style="cursor:pointer;display:inline-flex;align-items:center;gap:8px;color:#8B91A7;font-size:12px;font-weight:800;letter-spacing:.5px"><span style="width:12px;height:12px;background:#8B91A7;-webkit-mask:url(&quot;bd75dbf4-55bf-493b-918e-df0d9a27a1cd&quot;) center/contain no-repeat;mask:url(&quot;bd75dbf4-55bf-493b-918e-df0d9a27a1cd&quot;) center/contain no-repeat"></span>SCOREBOARD</.link>
              <span style="font-size:10px;font-weight:900;letter-spacing:2px;color:#565D73">{@kicker}</span>
            </div>

            <div style={"position:relative;overflow:hidden;border-radius:20px;border:1px solid #252A3A;background:linear-gradient(120deg,rgba(124,92,255,.12),#12141D 50%,rgba(200,255,46,.07));padding:18px 16px"}>
              <img src={@g.away && @g.away.logo} style="position:absolute;left:-44px;top:-40px;width:190px;height:190px;opacity:.09;pointer-events:none" alt="">
              <img src={@g.home && @g.home.logo} style="position:absolute;right:-44px;bottom:-48px;width:190px;height:190px;opacity:.09;pointer-events:none" alt="">
              <div style="position:absolute;right:-4px;top:-18px;font-family:'Archivo Black',sans-serif;font-style:italic;font-size:74px;color:transparent;-webkit-text-stroke:1px rgba(244,245,247,.07);pointer-events:none">VS</div>
              <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;position:relative">
                <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73">{@kicker}</span>
                <%= if @g.state == "in" do %>
                  <span style="display:inline-flex;align-items:center;gap:5px;background:rgba(255,69,87,.12);border:1px solid #FF4557;border-radius:999px;padding:3px 10px"><span style="width:5px;height:5px;border-radius:3px;background:#FF4557;animation:huw-blink 1.1s infinite"></span><span style="color:#FF4557;font-size:9px;font-weight:900;letter-spacing:1px">LIVE · {@g.status}</span></span>
                <% end %>
                <%= if @g.state == "pre" do %>
                  <span style="background:rgba(200,255,46,.12);border:1px solid rgba(200,255,46,.45);border-radius:999px;padding:3px 10px;color:var(--acc,#C8FF2E);font-size:9px;font-weight:900;letter-spacing:1px">UPCOMING</span>
                <% end %>
                <%= if @g.state == "post" do %>
                  <span style="background:#191C28;border:1px solid #252A3A;border-radius:999px;padding:3px 10px;color:#8B91A7;font-size:9px;font-weight:900;letter-spacing:1px">FINAL</span>
                <% end %>
              </div>
              <div style="display:flex;align-items:center;position:relative">
                <div style="width:100px;display:flex;flex-direction:column;align-items:center;gap:2px">
                  <img src={@g.away && @g.away.logo} style={"width:58px;height:58px;object-fit:contain;filter:drop-shadow(0 5px 10px rgba(124,92,255,.35))"} alt="">
                  <span style="font-family:'Archivo Black',sans-serif;font-style:italic;font-size:17px;margin-top:5px">{@g.away && @g.away.abbrev}</span>
                  <span style="font-size:8.5px;font-weight:800;letter-spacing:1px;color:#8B91A7">{@g.away && @g.away.name}</span>
                </div>
                <div style="flex:1;display:flex;align-items:center;justify-content:center;gap:14px">
                  <%= if @g.state == "pre" do %>
                    <div style="display:flex;flex-direction:column;align-items:center;gap:3px">
                      <span style="font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:34px;line-height:1;color:var(--acc,#C8FF2E)">{@g.status}</span>
                      <span style="font-size:8.5px;font-weight:900;letter-spacing:2px;color:#565D73">{start_label(@sport)}</span>
                    </div>
                  <% end %>
                  <%= if @g.state != "pre" do %>
                    <span style={"font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:clamp(38px,5.5vw,48px);line-height:1;color:#{lead_ink(@g, :away)}"}>{(@g.away && @g.away.score) || "0"}</span>
                    <%= if @g.state == "post" do %><span style="font-size:9px;font-weight:900;letter-spacing:1.5px;color:#565D73">FINAL</span><% end %>
                    <span style={"font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:clamp(38px,5.5vw,48px);line-height:1;color:#{lead_ink(@g, :home)}"}>{(@g.home && @g.home.score) || "0"}</span>
                  <% end %>
                </div>
                <div style="width:100px;display:flex;flex-direction:column;align-items:center;gap:2px">
                  <img src={@g.home && @g.home.logo} style={"width:58px;height:58px;object-fit:contain;filter:drop-shadow(0 5px 10px rgba(200,255,46,.3))"} alt="">
                  <span style="font-family:'Archivo Black',sans-serif;font-style:italic;font-size:17px;margin-top:5px">{@g.home && @g.home.abbrev}</span>
                  <span style="font-size:8.5px;font-weight:800;letter-spacing:1px;color:#8B91A7">{@g.home && @g.home.name}</span>
                </div>
              </div>
            </div>

            <%= if @box != nil and @linescores != [] do %>
              <div style="border-radius:14px;border:1px solid #252A3A;background:#12141D;overflow-x:auto;padding:8px 14px">
                <div style="display:flex;align-items:center;gap:10px">
                  <div style="display:flex;flex-direction:column;gap:5px;align-items:flex-start;margin-right:6px">
                    <span style="font-size:8px;font-weight:900;color:transparent;height:11px">.</span>
                    <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:12.5px;color:#565D73">{@g.away && @g.away.abbrev}</span>
                    <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:12.5px;color:#565D73">{@g.home && @g.home.abbrev}</span>
                  </div>
                  <%= for c <- @linescores do %>
                    <div style="display:flex;flex-direction:column;gap:5px;align-items:center;min-width:24px">
                      <span style="font-size:8px;font-weight:900;letter-spacing:.5px;color:#565D73;height:11px">{c.label}</span>
                      <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:12.5px;color:#B9BECF">{c.a}</span>
                      <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:12.5px;color:#B9BECF">{c.h}</span>
                    </div>
                  <% end %>
                  <div style="display:flex;flex-direction:column;gap:5px;align-items:center;min-width:30px;margin-left:6px">
                    <span style="font-size:8px;font-weight:900;color:#565D73;height:11px">{if @sport == "mlb", do: "R", else: "T"}</span>
                    <span style={"font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:13.5px;color:#{lead_ink(@g, :away)}"}>{(@g.away && @g.away.score) || "0"}</span>
                    <span style={"font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:13.5px;color:#{lead_ink(@g, :home)}"}>{(@g.home && @g.home.score) || "0"}</span>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @heaters != [] do %>
              <div style="display:flex;justify-content:space-between;padding:0 2px">
                <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73">{if @g.state == "post", do: "GAME HEATERS", else: "HEATING UP RIGHT NOW"}</span>
                <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73">FAN PTS</span>
              </div>
              <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">
                <%= for r <- @heaters do %>
                  <div style={"border-radius:14px;border:1px solid #252A3A;background:#12141D;padding:12px 8px;display:flex;flex-direction:column;align-items:center;gap:4px;text-align:center"}>
                    <img src={r[:img]} style={"width:38px;height:38px;border-radius:12px;object-fit:cover;object-position:top;background:#1A1E2B;border:1px solid #252A3A"} alt="">
                    <span style="font-size:10.5px;font-weight:700;max-width:94%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{r.name}</span>
                    <span style="font-size:8px;font-weight:900;letter-spacing:1.5px;color:#565D73">{r.team}</span>
                    <span style="font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:21px;line-height:1;color:var(--acc,#C8FF2E)">{r.pts}</span>
                    <span style="font-size:8.5px;color:#8B91A7;max-width:94%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{r.line}</span>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%= if @g.state == "pre" and @g.away[:probable] != nil and @g.home[:probable] != nil do %>
              <div style="display:flex;flex-direction:column;gap:8px">
                <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73;padding:0 2px">PROBABLE STARTERS</span>
                <div style="border-radius:14px;border:1px solid #252A3A;background:#12141D;padding:14px;display:flex;align-items:center;justify-content:space-between;gap:10px">
                  <div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:2px">
                    <span style="font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:#8B91A7">{@g.away.abbrev}</span>
                    <div style="width:46px;height:46px;border-radius:14px;background:#1A1E2B;border:1px solid #252A3A;display:flex;align-items:center;justify-content:center;margin:6px 0"><span style="font-weight:800;font-size:14px;color:#B9BECF">{initials(@g.away.probable[:name])}</span></div>
                    <span style="font-size:14px;font-weight:700">{@g.away.probable[:name]}</span>
                    <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:11.5px;letter-spacing:.4px;color:var(--acc,#C8FF2E)">{probable_line(@g.away.probable)}</span>
                  </div>
                  <span style="font-family:'Archivo Black',sans-serif;font-style:italic;font-size:15px;color:transparent;-webkit-text-stroke:1px #565D73">VS</span>
                  <div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:2px;align-items:flex-end;text-align:right">
                    <span style="font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:#8B91A7">{@g.home.abbrev}</span>
                    <div style="width:46px;height:46px;border-radius:14px;background:#1A1E2B;border:1px solid #252A3A;display:flex;align-items:center;justify-content:center;margin:6px 0"><span style="font-weight:800;font-size:14px;color:#B9BECF">{initials(@g.home.probable[:name])}</span></div>
                    <span style="font-size:14px;font-weight:700">{@g.home.probable[:name]}</span>
                    <span style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:11.5px;letter-spacing:.4px;color:var(--acc,#C8FF2E)">{probable_line(@g.home.probable)}</span>
                  </div>
                </div>
              </div>
            <% end %>

            <%= if @g.state == "pre" and leader_blocks(@g) != [] do %>
              <div style="display:flex;flex-direction:column;gap:8px">
                <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73;padding:0 2px">TEAM LEADERS</span>
                <div style="border-radius:14px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
                  <%= for b <- leader_blocks(@g) do %>
                    <div style="padding:12px 14px 15px;border-bottom:1px solid #1A1E2B">
                      <span style="font-size:9.5px;font-weight:800;letter-spacing:1.5px;color:#8B91A7">{b.team}</span>
                      <div style="display:flex;gap:10px;margin-top:8px">
                        <%= for l <- b.items do %>
                          <div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:2px">
                            <span style="font-size:8.5px;font-weight:900;letter-spacing:1px;color:#565D73">{l.cat}</span>
                            <span style="font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{l.name}</span>
                            <span style="font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:16px;color:var(--acc,#C8FF2E)">{l.val}</span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%= if @box != nil do %>
              <%= for t <- @box.teams do %>
                <div style="display:flex;flex-direction:column;gap:8px">
                  <div style="display:flex;align-items:center;gap:8px;margin-top:6px">
                    <img src={t.logo} style="width:19px;height:19px;object-fit:contain" alt="">
                    <span style="font-family:'Archivo Black',sans-serif;font-style:italic;font-size:15px;letter-spacing:1px">{t.head}</span>
                    <div style="flex:1;height:1px;background:#1A1E2B"></div>
                  </div>
                  <%= for g <- t.groups do %>
                    <div style="display:flex;flex-direction:column;gap:5px">
                      <%= if g.label != nil do %><span style="font-size:9px;font-weight:900;letter-spacing:1.5px;color:#565D73;margin-left:2px">{g.label}</span><% end %>
                      <div style="border-radius:14px;border:1px solid #252A3A;background:#12141D;overflow-x:auto">
                        <div style="min-width:480px">
                          <div style="display:flex;align-items:center;background:#191C28;padding:7px 0">
                            <span style="flex:1;min-width:130px;padding-left:14px;font-size:9px;font-weight:900;letter-spacing:.5px;color:#8B91A7">PLAYER</span>
                            <span style="width:48px;text-align:center;font-size:9px;font-weight:900;letter-spacing:.5px;color:var(--acc,#C8FF2E)">FAN</span>
                            <%= for c <- g.columns do %>
                              <span style="width:44px;text-align:center;font-size:9px;font-weight:900;letter-spacing:.5px;color:#8B91A7">{c}</span>
                            <% end %>
                          </div>
                          <%= for r <- g.rows do %>
                            <div style={"display:flex;align-items:center;border-bottom:1px solid #14171F;background:#{r.bg}"}>
                              <span style={"flex:1;min-width:130px;padding:10px 0 10px 14px;font-size:12px;font-weight:600;color:#{r.nameInk};white-space:nowrap;overflow:hidden;text-overflow:ellipsis"}>{r.name}</span>
                              <span style="width:48px;text-align:center;font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:15px;color:var(--acc,#C8FF2E)">{r.fan}</span>
                              <%= for s <- r.stats do %>
                                <span style="width:44px;text-align:center;font-family:'Barlow Condensed',sans-serif;font-weight:500;font-size:13px;color:#8B91A7">{s}</span>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <%= if @g.state == "in" and @sport == "mlb" do %>
                <span style="font-size:11px;color:#565D73;text-align:center;font-weight:600">Fantasy is approximate mid-game (extra-base hits finalize after the game).</span>
              <% end %>
            <% end %>

            <%= if @g.state == "pre" do %>
              <span style="font-size:9px;font-weight:900;letter-spacing:2px;color:#565D73;text-align:center;margin-top:4px">SCOUT BOTH ROSTERS BEFORE {String.upcase(start_word(@sport))}</span>
              <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px">
                <%= for t <- @rosters do %>
                  <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
                    <div style="padding:11px 16px;border-bottom:1px solid #1A1E2B"><span style="font-size:11px;font-weight:900;letter-spacing:1.5px;color:#8B91A7">{t.title}</span></div>
                    <%= for p <- t.rows do %>
                      <div style="display:flex;align-items:center;gap:11px;padding:9px 16px;border-bottom:1px solid #14171F">
                        <img src={p[:img]} style="width:36px;height:36px;flex:none;border-radius:11px;object-fit:cover;object-position:top;background:#1A1E2B" alt="">
                        <div style="display:flex;flex-direction:column;min-width:0"><span style="font-weight:700;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{p.name}</span><span style="font-size:10.5px;color:#565D73;font-weight:700">{p.pos}</span></div>
                        <div style="margin-left:auto;display:flex;flex-direction:column;align-items:flex-end"><span style="font-family:'Barlow Condensed',sans-serif;font-style:italic;font-weight:800;font-size:19px;line-height:1;color:var(--acc,#C8FF2E)">{p.proj}</span><span style="font-size:8px;font-weight:900;letter-spacing:1px;color:#565D73">PROJ</span></div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
    
    </Layouts.shell>
    """
  end

  # The leading side's score renders white; the trailing side dims.
  defp lead_ink(g, side) do
    a = int_score(g.away)
    h = int_score(g.home)

    cond do
      a == h -> "#F4F5F7"
      side == :away and a > h -> "#F4F5F7"
      side == :home and h > a -> "#F4F5F7"
      true -> "#8B91A7"
    end
  end

  defp int_score(nil), do: 0

  defp int_score(%{score: s}) do
    case Integer.parse(to_string(s || "0")) do
      {n, _} -> n
      :error -> 0
    end
  end
end
