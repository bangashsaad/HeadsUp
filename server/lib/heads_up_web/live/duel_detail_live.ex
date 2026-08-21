defmodule HeadsUpWeb.DuelDetailLive do
  @moduledoc """
  One duel, whole — the page the web never had: the full terms sheet, the
  scoring chart you're agreeing to before you accept, every seat's status on
  a group table, and the actions the duel's state allows. Party-scoped by
  `Contests.get_duel/2`, same as the phone.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Contests
  alias HeadsUp.Drafts.Lineup

  @impl true
  def mount(%{"id" => id_str}, _session, socket) do
    user = socket.assigns.current_user

    with {duel_id, ""} <- Integer.parse(id_str),
         %{} = duel <- Contests.get_duel(user, duel_id) do
      if connected?(socket), do: HeadsUpWeb.Endpoint.subscribe(HeadsUp.Contests.Events.topic(socket.assigns.current_user.id))
      {:ok, assign(socket, page_title: "Duel", duel: duel)}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "That duel isn't yours.") |> redirect(to: "/app/duels")}
    end
  end

  # The other side moved — re-read this duel (only this one).
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "duel_changed", payload: %{duel_id: id}}, socket) do
    if id == socket.assigns.duel.id do
      case Contests.get_duel(socket.assigns.current_user, id) do
        %{} = duel -> {:noreply, assign(socket, duel: duel)}
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("accept", _params, socket) do
    gated(socket, fn -> act(socket, :accept_challenge, "Locked in. Draft time.") end)
  end

  def handle_event("decline", _params, socket), do: act(socket, :decline_challenge, "Declined.")
  def handle_event("cancel", _params, socket), do: act(socket, :cancel_challenge, "Called off.")

  # Tampered or unknown events must not crash the socket.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp gated(socket, fun) do
    if HeadsUpWeb.UserAuth.verified_for_duels?(socket.assigns.current_user) do
      fun.()
    else
      {:noreply,
       socket
       |> put_flash(:error, "Verify your email to duel — takes a few seconds.")
       |> push_navigate(to: "/app/verify")}
    end
  end

  defp act(socket, fun, ok_msg) do
    user = socket.assigns.current_user

    case apply(Contests, fun, [user, socket.assigns.duel.id]) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, ok_msg) |> assign(duel: Contests.get_duel(user, socket.assigns.duel.id))}

      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't do that (#{inspect(reason)}).")}
    end
  end

  # --- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:16px;max-width:760px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;justify-content:space-between">
          <.link navigate={~p"/app/duels"} style="font-size:11px;font-weight:800;letter-spacing:1px;color:#8B91A7">← BACK TO DUELS</.link>
          <button
            id="share-duel"
            phx-hook="CopyLink"
            style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:10px;font-weight:900;letter-spacing:1px;border-radius:999px;padding:5px 14px;background:transparent"
          >
            SHARE THIS DUEL
          </button>
        </div>

        <%!-- the matchup --%>
        <div style="border-radius:18px;border:1px solid #252A3A;background:radial-gradient(420px 200px at 20% 0%,rgba(124,92,255,.16),transparent 70%),#12141D;padding:20px 22px;display:flex;flex-direction:column;gap:12px">
          <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            <span class="hu-cond" style="font-size:26px;line-height:1">{title(@duel, @current_user.id)}</span>
            <span style={"display:inline-flex;align-items:center;gap:6px;border:1px solid #{status_ink(@duel.status)};background:#{status_bg(@duel.status)};border-radius:999px;padding:4px 12px"}>
              <span style={"color:#{status_ink(@duel.status)};font-size:10px;font-weight:900;letter-spacing:1px"}>{String.upcase(@duel.status)}</span>
            </span>
          </div>
          <span style="font-size:12px;color:#8B91A7;font-weight:600">
            {String.upcase(@duel.sport)} · {@duel.roster_size} slots · {stake_text(@duel)} · {@duel.pick_clock_seconds}s clock
          </span>

          <%!-- seats (groups show everyone's answer) --%>
          <div :if={@duel.participants != []} style="display:flex;gap:8px;flex-wrap:wrap">
            <span
              :for={p <- @duel.participants}
              style={"display:inline-flex;align-items:center;gap:7px;border:1px solid #{seat_ink(p.status)};background:rgba(18,20,29,.8);border-radius:999px;padding:6px 13px"}
            >
              <span style="font-size:11px;font-weight:800">{p.user && p.user.username}</span>
              <span style={"font-size:9px;font-weight:900;letter-spacing:1px;color:#{seat_ink(p.status)}"}>{String.upcase(p.status)}</span>
            </span>
          </div>

          <%!-- actions by state --%>
          <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:2px">
            <button
              :if={respond?(@duel, @current_user.id)}
              phx-click="accept"
              class="hu-cond"
              style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;border:none"
            >
              ACCEPT →
            </button>
            <.link
              :if={respond?(@duel, @current_user.id) and @duel.opponent_id != nil}
              navigate={~p"/app/new?counter=#{@duel.id}"}
              class="hu-cond"
              style="cursor:pointer;border:1px solid #7C5CFF;color:#A794FF;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;text-decoration:none"
            >
              COUNTER
            </.link>
            <button
              :if={respond?(@duel, @current_user.id)}
              phx-click="decline"
              class="hu-cond"
              style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;background:transparent"
            >
              DECLINE
            </button>
            <button
              :if={@duel.status == "pending" and @duel.challenger_id == @current_user.id}
              phx-click="cancel"
              data-confirm="Call this challenge off?"
              class="hu-cond"
              style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;background:transparent"
            >
              CALL IT OFF
            </button>
            <.link
              :if={@duel.status in ~w(accepted drafting)}
              navigate={~p"/app/draft/#{@duel.id}"}
              class="hu-cond huw-pulse"
              style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;text-decoration:none"
            >
              ENTER THE ROOM →
            </.link>
            <.link
              :if={@duel.status == "drafted"}
              navigate={~p"/app/live/#{@duel.id}"}
              class="hu-cond huw-pulse"
              style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;text-decoration:none"
            >
              WATCH IT LIVE →
            </.link>
            <.link
              :if={@duel.status == "settled"}
              navigate={~p"/app/results/#{@duel.id}"}
              class="hu-cond"
              style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 26px;text-decoration:none"
            >
              SEE THE RECEIPT →
            </.link>
          </div>
        </div>

        <%!-- the terms --%>
        <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B">
            <span class="hu-cond" style="font-size:15px;letter-spacing:1px">THE TERMS</span>
          </div>
          <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr))">
            <.term label="LEAGUE" value={String.upcase(@duel.sport)} />
            <.term label="ROSTER" value={"#{@duel.roster_size} — #{shape_line(@duel)}"} />
            <.term label="STAKE" value={stake_text(@duel)} />
            <.term label="PICK CLOCK" value={"#{@duel.pick_clock_seconds} SECONDS"} />
            <.term label="SLATE" value={slate_text(@duel)} />
            <.term label="DRAFT" value={draft_text(@duel)} />
          </div>
        </div>

        <%!-- the scoring chart you're agreeing to --%>
        <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B;display:flex;justify-content:space-between;align-items:center">
            <span class="hu-cond" style="font-size:15px;letter-spacing:1px">SCORING CHART</span>
            <span style="font-size:10px;font-weight:800;letter-spacing:1px;color:#565D73">WHAT EVERY STAT PAYS</span>
          </div>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr))">
            <div
              :for={{cat, pts} <- chart(@duel)}
              style="display:flex;align-items:center;justify-content:space-between;padding:10px 16px;border-bottom:1px solid #14171F"
            >
              <span style="font-size:11px;font-weight:800;letter-spacing:.5px;color:#8B91A7">{cat}</span>
              <span class="hu-cond" style={"font-size:15px;color:#{if pts >= 0, do: "var(--acc,#C8FF2E)", else: "#FF4557"}"}>
                {points_text(pts)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp term(assigns) do
    ~H"""
    <div style="display:flex;flex-direction:column;gap:3px;padding:12px 16px;border-bottom:1px solid #14171F">
      <span style="font-size:9px;font-weight:900;letter-spacing:1.5px;color:#565D73">{@label}</span>
      <span style="font-size:12.5px;font-weight:800">{@value}</span>
    </div>
    """
  end

  # --- helpers -----------------------------------------------------------------

  defp title(duel, my_id) do
    others =
      cond do
        duel.participants != [] ->
          duel.participants |> Enum.reject(&(&1.user_id == my_id)) |> Enum.map(&(&1.user && &1.user.username))

        true ->
          other = if duel.challenger_id == my_id, do: duel.opponent, else: duel.challenger
          [other && other.username]
      end

    names = others |> Enum.reject(&is_nil/1) |> Enum.map(&String.upcase/1) |> Enum.join(" + ")
    "VS #{if names == "", do: "?", else: names}"
  end

  defp respond?(duel, my_id) do
    cond do
      duel.status != "pending" -> false
      duel.opponent_id == my_id -> true
      duel.participants != [] -> Enum.any?(duel.participants, &(&1.user_id == my_id and &1.status == "invited"))
      true -> false
    end
  end

  defp stake_text(%{stake_coins: 0}), do: "FRIENDLY — NO STAKE"
  defp stake_text(%{stake_coins: n} = d) do
    seats = max(length(d.participants), 2)
    "◎ #{n} EACH · POT ◎ #{n * seats}"
  end

  defp shape_line(duel) do
    duel.lineup_template
    |> Lineup.slots()
    |> Enum.map(& &1.label)
    |> Enum.chunk_by(& &1)
    |> Enum.map_join(" · ", fn
      [label] -> label
      [label | _] = run -> "#{length(run)} #{label}"
    end)
  end

  defp slate_text(%{slate_week: w}) when is_binary(w) and w != "", do: "WEEK #{w}"
  defp slate_text(%{slate_date: %Date{} = d}), do: d |> Calendar.strftime("%a %b %-d") |> String.upcase()
  defp slate_text(_), do: "NEXT SLATE"

  defp draft_text(%{draft_starts_at: %DateTime{} = at}),
    do: at |> Calendar.strftime("%b %-d · %-I:%M %p UTC") |> String.upcase()

  defp draft_text(_), do: "—"

  defp chart(duel) do
    (duel.scoring_rules || %{})
    |> Enum.sort_by(fn {_k, v} -> -abs(v * 1.0) end)
    |> Enum.map(fn {k, v} -> {k |> String.replace("_", " ") |> String.upcase(), v} end)
  end

  defp points_text(pts) when is_number(pts) do
    n = pts * 1.0
    "#{if n >= 0, do: "+", else: ""}#{:erlang.float_to_binary(n, decimals: 1)}"
  end

  defp status_ink("pending"), do: "#22E5FF"
  defp status_ink("countered"), do: "#A794FF"
  defp status_ink("accepted"), do: "#C8FF2E"
  defp status_ink("drafting"), do: "#FF4557"
  defp status_ink("drafted"), do: "#22E5FF"
  defp status_ink("settled"), do: "#C8FF2E"
  defp status_ink(_), do: "#565D73"

  defp status_bg(status), do: status |> status_ink() |> then(&"color-mix(in srgb, #{&1} 12%, transparent)")

  defp seat_ink("accepted"), do: "#C8FF2E"
  defp seat_ink("invited"), do: "#22E5FF"
  defp seat_ink("declined"), do: "#FF4557"
  defp seat_ink(_), do: "#565D73"
end
