defmodule HeadsUpWeb.YouLive do
  @moduledoc """
  The profile in the design's exact clothes: the radial hero with the record
  tiles, HOW YOU WIN with its three tabs (by league / by roster / by field,
  computed from real settled duels), YOUR CREW with group tabs and the
  rivalry-detail card (head-to-head, last 3 duels, CHALLENGE), ADD FRIEND
  with an inline search — plus the account controls the design omits but the
  product can't ship without.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUpWeb.Params

  alias HeadsUp.{Accounts, Contests, Social, Stats}

  @impl true
  def mount(params, _session, socket) do
    # ?rival=<id> — the Friends screen's crew rows land here with that
    # rivalry already open.
    sel =
      case Integer.parse(params["rival"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    {:ok,
     socket
     |> assign(page_title: "Profile", win_tab: "BY LEAGUE", crew_tab: "ALL", sel: sel, danger: nil, blocked: [])
     |> assign(adding: false, search: "", results: [], sent_ids: MapSet.new())
     |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user
    duels = Contests.list_duels(user) |> Enum.filter(&(&1.status == "settled"))
    h2h = Stats.head_to_head(user.id)
    friends = Social.list_friends(user)

    socket
    |> assign(
      requests: Social.list_incoming_requests(user),
      record: Stats.record_for(user.id),
      h2h_by_id: Map.new(h2h, &{&1.opponent.id, &1}),
      friends: friends,
      groups: Social.list_friend_groups(user),
      settled: duels,
    )
    |> then(fn s ->
      default =
        case {List.first(h2h), List.first(friends)} do
          {%{opponent: %{id: id}}, _} -> id
          {nil, %{id: id}} -> id
          _ -> nil
        end

      sel = s.assigns.sel || default
      riv = sel && Stats.rivalry(user.id, sel)
      assign(s, sel: sel, sel_riv: riv, sel_hist: (riv && riv.history) || [])
    end)
  end

  # --- events ----------------------------------------------------------------

  @impl true
  def handle_event("win-tab", %{"t" => t}, socket) when t in ["BY LEAGUE", "BY ROSTER", "BY FIELD"],
    do: {:noreply, assign(socket, win_tab: t)}

  def handle_event("crew-tab", %{"g" => g}, socket), do: {:noreply, assign(socket, crew_tab: g)}

  def handle_event("select", %{"id" => id}, socket) do
    id = Params.int(id)
    riv = Stats.rivalry(socket.assigns.current_user.id, id)
    {:noreply, assign(socket, sel: id, sel_riv: riv, sel_hist: riv.history)}
  end

  def handle_event("add-friend-toggle", _params, socket),
    do: {:noreply, assign(socket, adding: !socket.assigns.adding, search: "", results: [])}

  def handle_event("friend-search", %{"q" => q}, socket) do
    results = if String.length(q) >= 2, do: Social.search_users(q, socket.assigns.current_user), else: []
    {:noreply, assign(socket, search: q, results: results)}
  end

  def handle_event("request-accept", %{"id" => id}, socket) do
    case Social.accept_friend_request(socket.assigns.current_user, Params.int(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Friends. Now call them out.") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't accept that one.")}
    end
  end

  def handle_event("request-decline", %{"id" => id}, socket) do
    case Social.delete_friendship(socket.assigns.current_user, Params.int(id)) do
      :ok -> {:noreply, socket |> put_flash(:info, "Declined.") |> load()}
      _ -> {:noreply, put_flash(socket, :error, "Couldn't decline that one.")}
    end
  end

  def handle_event("friend-request", %{"id" => id}, socket) do
    id = Params.int(id)

    case Social.send_friend_request(socket.assigns.current_user, id) do
      {:ok, _} ->
        # Keep the results on screen and mark the row — vanishing the list
        # right after a tap reads as a glitch, not a success.
        {:noreply, update(socket, :sent_ids, &MapSet.put(&1, id))}

      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't send that request.")}
    end
  end

  def handle_event("block", %{"id" => id}, socket) do
    case Social.block_user(socket.assigns.current_user, Params.int(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Blocked.") |> assign(sel: nil) |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't block them.")}
    end
  end

  def handle_event("danger", %{"which" => which}, socket) do
    socket =
      if which == "blocked" and socket.assigns.danger != "blocked",
        do: assign(socket, blocked: Social.list_blocked(socket.assigns.current_user)),
        else: socket

    {:noreply, assign(socket, danger: if(socket.assigns.danger == which, do: nil, else: which))}
  end

  def handle_event("unblock", %{"id" => id}, socket) do
    Social.unblock_user(socket.assigns.current_user, Params.int(id))
    {:noreply, assign(socket, blocked: Social.list_blocked(socket.assigns.current_user))}
  end
  def handle_event("danger-close", _params, socket), do: {:noreply, assign(socket, danger: nil)}

  def handle_event("change-password", %{"current" => cur, "new" => new}, socket) do
    case Accounts.update_user_password(socket.assigns.current_user, cur, %{"password" => new}) do
      {:ok, _} ->
        {:noreply, socket |> assign(danger: nil) |> put_flash(:info, "Password changed.")}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "That current password isn't right.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "New password needs at least 8 characters.")}
    end
  end

  def handle_event("delete-account", %{"password" => password}, socket) do
    case Accounts.delete_account(socket.assigns.current_user, password) do
      {:ok, _} ->
        {:noreply, redirect(socket, to: "/")}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "Password doesn't match — account untouched.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't delete the account.")}
    end
  end

  # Tampered or unknown events must not crash the socket.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- render (the design's markup) -------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:18px;max-width:960px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <%!-- hero --%>
        <div style="display:flex;flex-wrap:wrap;align-items:center;gap:18px;background:radial-gradient(480px 220px at 8% 0%,rgba(124,92,255,.18),transparent 65%);border-radius:18px;padding:6px 8px">
          <div style="width:76px;height:76px;flex:none;border-radius:22px;background:linear-gradient(135deg,rgba(200,255,46,.25),#7C5CFF44);border:1px solid rgba(200,255,46,.4);display:flex;align-items:center;justify-content:center">
            <span style="color:var(--acc,#C8FF2E);font-weight:900;font-size:30px">
              {@current_user.username |> String.first() |> String.upcase()}
            </span>
          </div>
          <div style="display:flex;flex-direction:column;gap:2px">
            <span class="hu-black" style="font-size:30px;letter-spacing:-.5px">{@current_user.username}</span>
            <span style="font-size:12px;color:#8B91A7;font-weight:700">
              Duelist since {Calendar.strftime(@current_user.inserted_at, "%B %Y")}{heater(@record)}
            </span>
          </div>
          <div style="margin-left:auto;display:flex;flex-wrap:wrap;justify-content:flex-end;gap:12px 26px;padding-right:8px">
            <div style="display:flex;flex-direction:column;align-items:flex-end">
              <span class="hu-cond" style="font-size:38px;line-height:1">{@record.wins}–{@record.losses}</span>
              <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#565D73">RECORD</span>
            </div>
            <div style="display:flex;flex-direction:column;align-items:flex-end">
              <span class="hu-cond" style="font-size:38px;line-height:1">{streak_tile(@record)}</span>
              <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#565D73">STREAK</span>
            </div>
            <div style="display:flex;flex-direction:column;align-items:flex-end">
              <span class="hu-cond" style="font-size:38px;line-height:1;color:var(--acc,#C8FF2E)">{win_pct(@record)}%</span>
              <span style="font-size:10px;font-weight:800;letter-spacing:1.5px;color:#565D73">WIN RATE</span>
            </div>
          </div>
        </div>

        <%!-- HOW YOU WIN --%>
        <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <div style="padding:13px 18px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">HOW YOU WIN</span>
            <div style="margin-left:auto;display:flex;gap:6px">
              <button :for={t <- ["BY LEAGUE", "BY ROSTER", "BY FIELD"]} phx-click="win-tab" phx-value-t={t} style={tab_pill(@win_tab == t)}>
                {t}
              </button>
            </div>
          </div>
          <div style="display:grid;grid-template-columns:repeat(3,1fr)">
            <div :for={row <- win_rows(@win_tab, @settled, @current_user.id)} style="padding:16px 18px;border-right:1px solid #14171F;display:flex;flex-direction:column;gap:4px">
              <span style="font-size:10px;font-weight:900;letter-spacing:1.5px;color:#565D73">{row.label}</span>
              <span class="hu-cond" style={"font-size:30px;color:#{row.ink}"}>{row.rec}</span>
              <span style="font-size:11px;color:#8B91A7;font-weight:600">{row.note}</span>
            </div>
            <p :if={win_rows(@win_tab, @settled, @current_user.id) == []} style="grid-column:1/-1;padding:20px;font-size:12px;color:#565D73;font-weight:600">
              Finish a duel and the splits show up here.
            </p>
          </div>
        </div>

        <%!-- crew + rivalry detail --%>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:18px;align-items:start">
          <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
            <div style="padding:13px 18px;border-bottom:1px solid #1A1E2B;display:flex;flex-wrap:wrap;align-items:center;gap:10px">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">YOUR CREW</span>
              <div :if={@groups != []} style="display:flex;flex-wrap:wrap;gap:6px;margin-left:6px">
                <button :for={g <- [%{name: "ALL"} | @groups]} phx-click="crew-tab" phx-value-g={g.name} style={tab_pill(@crew_tab == g.name)}>
                  {String.upcase(g.name)}
                </button>
              </div>
              <button phx-click="add-friend-toggle" style="cursor:pointer;margin-left:auto;display:inline-flex;align-items:center;gap:7px;border:1px solid var(--acc,#C8FF2E);color:var(--acc,#C8FF2E);border-radius:999px;padding:6px 14px;background:transparent">
                <span style="width:13px;height:13px;background:var(--acc,#C8FF2E);-webkit-mask:url('/icons/d19f313e.svg') center/contain no-repeat;mask:url('/icons/d19f313e.svg') center/contain no-repeat">
                </span>
                <span style="font-size:11px;font-weight:800;letter-spacing:.5px">ADD FRIEND</span>
              </button>
            </div>

            <div :if={@adding} style="padding:12px 18px;border-bottom:1px solid #1A1E2B">
              <form phx-change="friend-search" id="friend-search" style="display:flex;align-items:center;gap:8px;background:#0D0F16;border:1px solid #252A3A;border-radius:999px;padding:8px 14px">
                <span style="width:13px;height:13px;flex:none;background:#565D73;-webkit-mask:url('/icons/bd194911.svg') center/contain no-repeat;mask:url('/icons/bd194911.svg') center/contain no-repeat">
                </span>
                <input
                  type="text"
                  name="q"
                  value={@search}
                  autocomplete="off"
                  placeholder="Find a duelist by name…"
                  style="flex:1;min-width:0;background:transparent;border:none;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:12.5px;outline:none"
                />
              </form>
              <%!-- search_users returns {user, relationship, friendship_id} —
                    the relationship drives which button this row gets. --%>
              <div :for={r <- @results} style="display:flex;align-items:center;gap:10px;padding:9px 4px">
                <span style="font-weight:800;font-size:12.5px">{r.user.username}</span>
                <button
                  :if={r.relationship == "none" and not MapSet.member?(@sent_ids, r.user.id)}
                  phx-click="friend-request"
                  phx-value-id={r.user.id}
                  class="hu-cond"
                  style="cursor:pointer;margin-left:auto;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:13px;border-radius:999px;padding:5px 14px;border:none"
                >
                  CALL THEM IN
                </button>
                <span
                  :if={r.relationship == "request_sent" or MapSet.member?(@sent_ids, r.user.id)}
                  class="hu-cond"
                  style="margin-left:auto;border:1px solid rgba(200,255,46,.4);color:var(--acc,#C8FF2E);font-size:13px;border-radius:999px;padding:5px 14px"
                >
                  SENT ✓
                </span>
                <span
                  :if={r.relationship == "friends"}
                  class="hu-cond"
                  style="margin-left:auto;color:#8B91A7;font-size:13px;border:1px solid #252A3A;border-radius:999px;padding:5px 14px"
                >
                  ALREADY CREW
                </span>
                <button
                  :if={r.relationship == "request_received"}
                  phx-click="request-accept"
                  phx-value-id={r.friendship_id}
                  class="hu-cond"
                  style="cursor:pointer;margin-left:auto;background:#7C5CFF;color:#fff;font-size:13px;border-radius:999px;padding:5px 14px;border:none"
                >
                  THEY ASKED FIRST — ACCEPT
                </button>
              </div>
              <p :if={@results == [] and String.length(@search) >= 2} style="padding:10px 4px;font-size:11.5px;color:#565D73;font-weight:600">
                Nobody by that name — usernames match anywhere, so try any part of it.
              </p>
            </div>

            <div :if={@requests != []} style="border-bottom:1px solid #1A1E2B">
              <span style="display:block;padding:10px 18px 4px;font-size:9.5px;font-weight:900;letter-spacing:2px;color:#FFB021">
                WANTS IN · {length(@requests)}
              </span>
              <div :for={req <- @requests} style="display:flex;align-items:center;gap:12px;padding:9px 18px">
                <div style="width:32px;height:32px;flex:none;border-radius:10px;background:rgba(255,176,33,.15);display:flex;align-items:center;justify-content:center;font-weight:800;font-size:12px;color:#FFB021">
                  {req.requester.username |> String.slice(0, 2) |> String.upcase()}
                </div>
                <span style="font-weight:800;font-size:13px;flex:1;min-width:0">{req.requester.username}</span>
                <button
                  phx-click="request-accept"
                  phx-value-id={req.id}
                  class="hu-cond"
                  style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:13px;border-radius:999px;padding:5px 14px;border:none"
                >
                  ACCEPT
                </button>
                <button
                  phx-click="request-decline"
                  phx-value-id={req.id}
                  class="hu-cond"
                  style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:13px;border-radius:999px;padding:5px 14px;background:transparent"
                >
                  DECLINE
                </button>
              </div>
            </div>

            <div :if={@friends == []}>
              <div style="display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F;opacity:.55">
                <div style="width:36px;height:36px;flex:none;border-radius:11px;border:1px dashed #3A4157"></div>
                <div style="display:flex;flex-direction:column;gap:6px">
                  <div style="width:110px;height:9px;border-radius:5px;background:#1A1E2B"></div>
                  <div style="width:150px;height:7px;border-radius:4px;background:#14171F"></div>
                </div>
              </div>
              <div style="display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F;opacity:.3">
                <div style="width:36px;height:36px;flex:none;border-radius:11px;border:1px dashed #3A4157"></div>
                <div style="display:flex;flex-direction:column;gap:6px">
                  <div style="width:120px;height:9px;border-radius:5px;background:#1A1E2B"></div>
                  <div style="width:80px;height:7px;border-radius:4px;background:#14171F"></div>
                </div>
              </div>
              <div style="padding:22px 18px 24px;display:flex;flex-direction:column;align-items:center;gap:8px;text-align:center">
                <span class="hu-cond" style="font-size:26px;line-height:1">RIDING SOLO<span style="color:var(--acc,#C8FF2E)">.</span></span>
                <span style="font-size:12px;color:#8B91A7;font-weight:600;max-width:280px">
                  Every rivalry starts with a username. Search your people and call them out.
                </span>
                <button
                  phx-click="add-friend-toggle"
                  class="hu-cond"
                  style="cursor:pointer;margin-top:4px;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:15px;border-radius:999px;padding:10px 24px;border:none"
                >
                  FIND YOUR RIVALS →
                </button>
              </div>
            </div>
            <div
              :for={f <- crew(@friends, @groups, @crew_tab)}
              phx-click="select"
              phx-value-id={f.id}
              style={"cursor:pointer;display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F;background:#{if @sel == f.id, do: "#151827", else: "transparent"}"}
            >
              <div style={"width:36px;height:36px;flex:none;border-radius:11px;background:#{crew_bg(@h2h_by_id, f.id)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;color:#{crew_ink(@h2h_by_id, f.id)}"}>
                {f.username |> String.slice(0, 2) |> String.upcase()}
              </div>
              <div style="display:flex;flex-direction:column;min-width:0">
                <span style="font-weight:800;font-size:13.5px">{f.username}</span>
                <span style="font-size:10.5px;color:#565D73;font-weight:700">{groups_of(f.id, @groups)}</span>
              </div>
              <span class="hu-cond" style={"margin-left:auto;font-size:22px;color:#{crew_ink(@h2h_by_id, f.id)}"}>
                {crew_rec(@h2h_by_id, f.id)}
              </span>
              <span style="width:13px;height:13px;flex:none;background:#565D73;-webkit-mask:url('/icons/b6200cf4.svg') center/contain no-repeat;mask:url('/icons/b6200cf4.svg') center/contain no-repeat">
              </span>
            </div>
          </div>

          <%!-- rivalry detail --%>
          <div :if={@sel} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden;display:flex;flex-direction:column">
            <div style="padding:16px;background:linear-gradient(150deg,rgba(124,92,255,.16),#12141D 70%);display:flex;align-items:center;gap:12px;border-bottom:1px solid #1A1E2B">
              <div style="width:44px;height:44px;flex:none;border-radius:13px;background:rgba(124,92,255,.18);display:flex;align-items:center;justify-content:center;font-weight:800;font-size:15px;color:#9F8BFF">
                {sel_name(assigns) |> String.slice(0, 2) |> String.upcase()}
              </div>
              <div style="display:flex;flex-direction:column">
                <span style="font-weight:900;font-size:16px">{sel_name(assigns)}</span>
                <span style="font-size:11px;color:#8B91A7;font-weight:700">{sel_since(assigns)}</span>
              </div>
              <button
                phx-click="block"
                phx-value-id={@sel}
                data-confirm={"Block #{sel_name(assigns)}? Shared live duels get cancelled and you disappear from each other."}
                style="cursor:pointer;margin-left:auto;font-size:10px;font-weight:800;letter-spacing:.5px;color:#565D73;background:transparent;border:none"
              >
                BLOCK
              </button>
            </div>
            <div style="padding:18px 16px;display:flex;align-items:center;justify-content:center;gap:26px">
              <div style="display:flex;flex-direction:column;align-items:center">
                <span style="font-size:10px;font-weight:900;letter-spacing:1px;color:var(--acc,#C8FF2E)">YOU</span>
                <span class="hu-cond" style={"font-size:52px;line-height:1;color:#{if sel_w(assigns) >= sel_l(assigns), do: "var(--acc,#C8FF2E)", else: "#F4F5F7"}"}>
                  {sel_w(assigns)}
                </span>
              </div>
              <span class="hu-black" style="font-size:15px;color:#565D73">VS</span>
              <div style="display:flex;flex-direction:column;align-items:center">
                <span style="font-size:10px;font-weight:900;letter-spacing:1px;color:#8B91A7">THEM</span>
                <span class="hu-cond" style={"font-size:52px;line-height:1;color:#{if sel_l(assigns) > sel_w(assigns), do: "#FF4557", else: "#8B91A7"}"}>
                  {sel_l(assigns)}
                </span>
              </div>
            </div>
            <%!-- bragging-rights tiles (the phone design's CURRENT RUN / AVG MARGIN / BEST WIN) --%>
            <div :if={@sel_riv} style="padding:0 16px 10px;display:grid;grid-template-columns:repeat(3,1fr);gap:8px">
              <div style="background:#0D0F16;border:1px solid #252A3A;border-radius:12px;padding:11px 0;display:flex;flex-direction:column;align-items:center">
                <span class="hu-cond" style={"font-size:19px;color:#{run_ink(@sel_riv.run)}"}>{@sel_riv.run || "—"}</span>
                <span style="font-size:8.5px;font-weight:900;letter-spacing:1px;color:#565D73;margin-top:2px">CURRENT RUN</span>
              </div>
              <div style="background:#0D0F16;border:1px solid #252A3A;border-radius:12px;padding:11px 0;display:flex;flex-direction:column;align-items:center">
                <span class="hu-cond" style="font-size:19px">{signed(@sel_riv.avg_margin)}</span>
                <span style="font-size:8.5px;font-weight:900;letter-spacing:1px;color:#565D73;margin-top:2px">AVG MARGIN</span>
              </div>
              <div style="background:#0D0F16;border:1px solid #252A3A;border-radius:12px;padding:11px 0;display:flex;flex-direction:column;align-items:center">
                <span class="hu-cond" style="font-size:19px">{signed(@sel_riv.best_win)}</span>
                <span style="font-size:8.5px;font-weight:900;letter-spacing:1px;color:#565D73;margin-top:2px">BEST WIN</span>
              </div>
            </div>
            <div style="padding:0 16px 8px;display:flex;flex-direction:column;gap:7px">
              <div :if={@sel_riv && @sel_riv.form != []} style="display:flex;align-items:center;gap:5px">
                <span style="font-size:9px;font-weight:900;letter-spacing:1.5px;color:#565D73;margin-right:3px">LAST {length(@sel_riv.form)}</span>
                <span
                  :for={l <- @sel_riv.form}
                  style={"width:20px;height:20px;border-radius:7px;background:#{hist_bg(%{outcome: form_outcome(l)})};border:1px solid #{hist_ink(%{outcome: form_outcome(l)})};color:#{hist_ink(%{outcome: form_outcome(l)})};font-size:9.5px;font-weight:900;display:flex;align-items:center;justify-content:center"}
                >
                  {l}
                </span>
              </div>
              <span style="font-size:10px;font-weight:900;letter-spacing:1.5px;color:#565D73">LAST {length(@sel_hist)} DUELS</span>
              <p :if={@sel_hist == []} style="font-size:11px;color:#565D73;font-weight:600">Nothing settled between you yet.</p>
              <div :for={hst <- @sel_hist} style="display:flex;align-items:center;gap:9px;border:1px solid #1A1E2B;border-radius:11px;padding:8px 12px">
                <span style={"width:18px;height:18px;flex:none;border-radius:6px;background:#{hist_bg(hst)};border:1px solid #{hist_ink(hst)};color:#{hist_ink(hst)};font-size:9.5px;font-weight:900;display:flex;align-items:center;justify-content:center"}>
                  {hist_letter(hst)}
                </span>
                <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                  <span style="font-size:11.5px;font-weight:700;color:#C7CBD9">{fmt_pts(hst.my_points)} – {fmt_pts(hst.their_points)}</span>
                  <span :if={hst.story} style="font-size:10px;color:#8B91A7;font-weight:600">{hst.story}</span>
                </div>
                <span style="margin-left:auto;font-size:10px;font-weight:800;color:#565D73">
                  {Calendar.strftime(hst.settled_at, "%b %-d") |> String.upcase()}
                </span>
              </div>
            </div>
            <div style="padding:14px 16px 16px">
              <.link
                navigate={~p"/app/new?rival=#{@sel}"}
                class="hu-cond"
                style="cursor:pointer;display:block;background:var(--acc,#C8FF2E);color:#0A0B10;border-radius:12px;padding:13px;text-align:center;font-size:18px;letter-spacing:.5px"
              >
                CHALLENGE {sel_name(assigns) |> String.upcase()} →
              </.link>
            </div>
          </div>
        </div>

        <%!-- account (his row list + the verified badge) --%>
        <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <div style="padding:13px 18px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between">
            <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">ACCOUNT</span>
            <span :if={@current_user.email_verified_at} style="display:inline-flex;align-items:center;gap:6px">
              <span style="width:12px;height:12px;background:var(--acc,#C8FF2E);-webkit-mask:url('/icons/6cde3d56.svg') center/contain no-repeat;mask:url('/icons/6cde3d56.svg') center/contain no-repeat">
              </span>
              <span style="font-size:10px;font-weight:800;color:var(--acc,#C8FF2E)">EMAIL VERIFIED</span>
            </span>
            <.link :if={!@current_user.email_verified_at} navigate={~p"/app/verify"} style="font-size:10px;font-weight:800;color:#FFB021">
              VERIFY EMAIL →
            </.link>
          </div>
          <div phx-click="danger" phx-value-which="password" style="cursor:pointer;display:flex;align-items:center;justify-content:space-between;padding:12px 18px;border-bottom:1px solid #14171F">
            <span style="font-size:13px;font-weight:700">Change password</span>
            <span style="width:13px;height:13px;background:#565D73;-webkit-mask:url('/icons/b6200cf4.svg') center/contain no-repeat;mask:url('/icons/b6200cf4.svg') center/contain no-repeat">
            </span>
          </div>
          <.link href="/logout" method="delete" style="display:flex;align-items:center;justify-content:space-between;padding:12px 18px;border-bottom:1px solid #14171F">
            <span style="font-size:13px;font-weight:700;color:#F4F5F7">Sign out</span>
            <span style="width:13px;height:13px;background:#565D73;-webkit-mask:url('/icons/b6200cf4.svg') center/contain no-repeat;mask:url('/icons/b6200cf4.svg') center/contain no-repeat">
            </span>
          </.link>
          <div phx-click="danger" phx-value-which="blocked" style="cursor:pointer;display:flex;align-items:center;justify-content:space-between;padding:12px 18px;border-bottom:1px solid #14171F">
            <span style="font-size:13px;font-weight:700">Blocked players</span>
            <span style="width:13px;height:13px;background:#565D73;-webkit-mask:url('/icons/b6200cf4.svg') center/contain no-repeat;mask:url('/icons/b6200cf4.svg') center/contain no-repeat">
            </span>
          </div>
          <div :if={@danger == "blocked"} style="padding:0 18px 16px;display:flex;flex-direction:column;gap:8px">
            <p :if={@blocked == []} style="font-size:11.5px;color:#565D73;font-weight:600">
              Nobody's blocked. Block someone from their rivalry page — it cancels shared duels and they can't reach you.
            </p>
            <div
              :for={u <- @blocked}
              style="display:flex;align-items:center;justify-content:space-between;gap:10px;border:1px solid #252A3A;background:#0D0F16;border-radius:11px;padding:9px 13px"
            >
              <span style="font-size:12.5px;font-weight:800">{u.username}</span>
              <button
                phx-click="unblock"
                phx-value-id={u.id}
                style="cursor:pointer;background:transparent;border:1px solid #3A4157;color:#B9BECF;font-size:10.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:5px 12px"
              >
                UNBLOCK
              </button>
            </div>
          </div>
          <div phx-click="danger" phx-value-which="delete" style="cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 18px">
            <span style="font-size:13px;font-weight:700;color:#FF4557">Delete account</span>
            <span style="font-size:10.5px;color:#565D73;font-weight:600">Permanent — duels are anonymized</span>
          </div>

          <div :if={@danger == "password"} style="padding:0 18px 16px">
            <form phx-submit="change-password" style="display:flex;flex-wrap:wrap;gap:8px">
              <input type="password" name="current" required placeholder="Current password" style={acct_input()} />
              <input type="password" name="new" required minlength="8" placeholder="New password (8+)" style={acct_input()} />
              <button type="submit" class="hu-cond" style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:14px;border-radius:10px;padding:9px 18px;border:none">
                CHANGE IT
              </button>
            </form>
          </div>

          <div :if={@danger == "delete"} style="margin:0 18px 16px;border:1px solid rgba(255,69,87,.4);background:rgba(255,69,87,.05);border-radius:12px;padding:14px">
            <p style="font-size:12px;font-weight:800;color:#FF4557">This is permanent.</p>
            <p style="font-size:11px;color:#8B91A7;font-weight:600;margin-top:3px">
              Your account is anonymized and unusable. Finished duels stay on your rivals' records, but your name comes off everything.
            </p>
            <form phx-submit="delete-account" style="display:flex;flex-wrap:wrap;gap:8px;margin-top:10px">
              <input type="password" name="password" required placeholder="Your password, to confirm" style={acct_input()} />
              <button type="submit" data-confirm="Absolutely sure? There is no undo." class="hu-cond" style="cursor:pointer;background:#FF4557;color:#fff;font-size:14px;border-radius:10px;padding:9px 18px;border:none">
                DELETE MY ACCOUNT
              </button>
            </form>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  # --- helpers ---------------------------------------------------------------

  defp heater(%{streak: %{count: c, type: "win"}}) when c >= 2, do: " · 🔥 #{c}-duel heater"
  defp heater(_), do: ""

  defp win_pct(%{wins: w, losses: l}) when w + l > 0, do: round(w / (w + l) * 100)
  defp win_pct(_), do: 0

  defp tab_pill(true),
    do:
      "cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.5px;color:#0A0B10;background:var(--acc,#C8FF2E);border:1px solid var(--acc,#C8FF2E);border-radius:999px;padding:5px 12px"

  defp tab_pill(false),
    do:
      "cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.5px;color:#8B91A7;background:transparent;border:1px solid #252A3A;border-radius:999px;padding:5px 12px"

  defp acct_btn,
    do:
      "cursor:pointer;font-size:11px;font-weight:800;letter-spacing:.5px;color:#F4F5F7;background:transparent;border:1px solid #252A3A;border-radius:999px;padding:8px 16px"

  defp acct_input,
    do:
      "flex:1;min-width:180px;background:#0D0F16;border:1px solid #252A3A;border-radius:10px;padding:9px 13px;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:12.5px;outline:none"

  # The three HOW YOU WIN splits, computed from real settled duels.
  defp win_rows("BY LEAGUE", settled, me) do
    settled
    |> Enum.group_by(& &1.sport)
    |> Enum.map(fn {sport, ds} -> split_row(String.upcase(sport), ds, me) end)
    |> Enum.sort_by(& &1.label)
  end

  defp win_rows("BY ROSTER", settled, me) do
    settled
    |> Enum.group_by(& &1.roster_size)
    |> Enum.map(fn {n, ds} -> split_row("#{n} SLOTS", ds, me) end)
    |> Enum.sort_by(& &1.label)
  end

  defp win_rows("BY FIELD", settled, me) do
    {h2h, group} = Enum.split_with(settled, &(&1.opponent_id != nil))

    [split_row("HEAD-TO-HEAD", h2h, me), split_row("3–4 DRAFTERS", group, me)]
    |> Enum.reject(&(&1.rec == "0–0"))
  end

  defp split_row(label, duels, me) do
    w = Enum.count(duels, &(&1.winner_id == me))
    l = Enum.count(duels, &(&1.winner_id != me and &1.winner_id != nil))

    %{
      label: label,
      rec: "#{w}–#{l}",
      ink: if(w >= l and w > 0, do: "var(--acc,#C8FF2E)", else: "#C7CBD9"),
      note:
        cond do
          w + l == 0 -> "No decisions yet"
          w > l -> "Your bread and butter"
          w == l -> "Coin-flip territory"
          true -> "Needs work"
        end
    }
  end

  defp crew(friends, _groups, "ALL"), do: friends

  defp crew(friends, groups, tab) do
    case Enum.find(groups, &(&1.name == tab)) do
      nil -> friends
      g -> Enum.filter(friends, &(&1.id in g.member_ids))
    end
  end

  defp groups_of(id, groups) do
    names = groups |> Enum.filter(&(id in &1.member_ids)) |> Enum.map(&String.upcase(&1.name))
    if names == [], do: "NO GROUP", else: Enum.join(names, " · ")
  end

  defp crew_rec(h2h, id) do
    case Map.get(h2h, id) do
      nil -> "0–0"
      r -> "#{r.wins}–#{r.losses}"
    end
  end

  defp crew_ink(h2h, id) do
    case Map.get(h2h, id) do
      nil -> "#565D73"
      r -> if r.wins >= r.losses, do: "#C8FF2E", else: "#FF4557"
    end
  end

  defp crew_bg(h2h, id) do
    case Map.get(h2h, id) do
      nil -> "rgba(139,145,167,.12)"
      r -> if r.wins >= r.losses, do: "rgba(200,255,46,.12)", else: "rgba(255,69,87,.14)"
    end
  end

  defp sel_name(%{sel: sel, friends: friends, h2h_by_id: h2h}) do
    cond do
      f = Enum.find(friends, &(&1.id == sel)) -> f.username
      r = Map.get(h2h, sel) -> r.opponent.username
      true -> "them"
    end
  end

  defp sel_since(%{sel_hist: []}), do: "No duels between you yet"
  defp sel_since(%{sel_hist: hist}), do: "#{length(hist)} settled duels"

  defp sel_w(%{sel: sel, h2h_by_id: h2h}), do: (Map.get(h2h, sel) || %{wins: 0}).wins
  defp sel_l(%{sel: sel, h2h_by_id: h2h}), do: (Map.get(h2h, sel) || %{losses: 0}).losses

  defp run_ink("W" <> _), do: "var(--acc,#C8FF2E)"
  defp run_ink("L" <> _), do: "#FF4557"
  defp run_ink(_), do: "#8B91A7"

  defp signed(nil), do: "—"
  defp signed(n) when n >= 0, do: "+#{fmt_pts(n)}"
  defp signed(n), do: "−#{fmt_pts(abs(n))}"

  defp form_outcome("W"), do: :win
  defp form_outcome("L"), do: :loss
  defp form_outcome(_), do: :tie

  defp hist_letter(%{outcome: :win}), do: "W"
  defp hist_letter(%{outcome: :loss}), do: "L"
  defp hist_letter(_), do: "T"

  defp hist_ink(%{outcome: :win}), do: "#C8FF2E"
  defp hist_ink(%{outcome: :loss}), do: "#FF4557"
  defp hist_ink(_), do: "#8B91A7"

  defp hist_bg(%{outcome: :win}), do: "rgba(200,255,46,.12)"
  defp hist_bg(%{outcome: :loss}), do: "rgba(255,69,87,.10)"
  defp hist_bg(_), do: "rgba(139,145,167,.10)"

  defp fmt_pts(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp fmt_pts(n), do: to_string(n)

  defp streak_tile(%{streak: %{count: c, type: t}}) when c > 0 do
    prefix = if t == "win", do: "🔥 W", else: "L"
    "#{prefix}#{c}"
  end

  defp streak_tile(_), do: "—"
end
