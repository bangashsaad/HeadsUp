defmodule HeadsUpWeb.DuelsLive do
  @moduledoc """
  The duels list in the design's exact clothes: avatar-tile rows with status
  badges on the active tab; W/L-railed rows with the coin swing and REMATCH
  on the past tab, dead challenges dimmed below. DOM and inline styles from
  the design export; data and actions are the app's.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Contests

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Duels", tab: "active") |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user
    duels = Contests.list_duels(user)

    assign(socket,
      active: Enum.filter(duels, &(&1.status in ~w(pending accepted drafting drafted))),
      settled: Enum.filter(duels, &(&1.status == "settled")),
      dead: Enum.filter(duels, &(&1.status in ~w(declined cancelled expired)))
    )
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(active past),
    do: {:noreply, assign(socket, tab: tab)}

  def handle_event("accept", %{"id" => id}, socket), do: act(socket, :accept_challenge, id, "Locked in. Draft time.")
  def handle_event("decline", %{"id" => id}, socket), do: act(socket, :decline_challenge, id, "Declined.")
  def handle_event("cancel", %{"id" => id}, socket), do: act(socket, :cancel_challenge, id, "Called off.")
  def handle_event("rematch", %{"id" => id}, socket), do: act(socket, :rematch, id, "Rematch sent — same terms.")

  defp act(socket, fun, id, ok_msg) do
    case apply(Contests, fun, [socket.assigns.current_user, String.to_integer(id)]) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, ok_msg) |> load()}
      {:error, reason} when is_binary(reason) -> {:noreply, put_flash(socket, :error, reason)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Couldn't do that (#{inspect(reason)}).")}
    end
  end

  # --- render (the design's markup) ------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div style="flex:1;display:flex;flex-direction:column;gap:16px;max-width:860px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap">
          <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">DUELS</span>
          <div style="display:flex;gap:6px">
            <button
              :for={{key, label} <- [{"active", "ACTIVE"}, {"past", "PAST"}]}
              phx-click="tab"
              phx-value-tab={key}
              style={tab_style(@tab == key)}
            >
              {label}
            </button>
            <.link navigate={~p"/app/new"} class="hu-cond" style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:14px;border-radius:999px;padding:8px 18px;white-space:nowrap">
              + NEW
            </.link>
          </div>
        </div>

        <div :if={@tab == "active"} style="display:flex;flex-direction:column;gap:10px">
          <p :if={@active == []} style="font-size:12px;color:#565D73;font-weight:600;padding:24px 0;text-align:center">
            Nothing going. Call somebody out.
          </p>
          <div :for={d <- @active} style={"border-radius:14px;border:1px solid #{card_border(d)};background:#12141D;padding:14px 16px"}>
            <div style="display:flex;align-items:center;gap:12px">
              <div style={"width:38px;height:38px;flex:none;border-radius:12px;background:#{av_bg(d, @current_user.id)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:14px;color:#{av_ink(d, @current_user.id)}"}>
                {initials(title(d, @current_user.id))}
              </div>
              <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                <span style="font-weight:800;font-size:14px">{title(d, @current_user.id)}</span>
                <span style="font-size:11px;color:#8B91A7;font-weight:600;margin-top:2px">{meta_line(d)}</span>
              </div>
              <span style={"flex:none;display:inline-flex;align-items:center;gap:6px;background:#{badge_bg(d, @current_user.id)};border:1px solid #{badge_ink(d, @current_user.id)};border-radius:999px;padding:4px 12px"}>
                <span :if={blink?(d)} class="huw-blink" style={"width:5px;height:5px;border-radius:3px;background:#{badge_ink(d, @current_user.id)}"}>
                </span>
                <span style={"color:#{badge_ink(d, @current_user.id)};font-size:10px;font-weight:900;letter-spacing:1px"}>
                  {badge(d, @current_user.id)}
                </span>
              </span>
            </div>

            <div :if={respond?(d, @current_user.id)} style="display:flex;gap:8px;margin-top:12px">
              <button phx-click="accept" phx-value-id={d.id} class="hu-cond" style="cursor:pointer;flex:1;text-align:center;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:15px;border-radius:9px;padding:8px 0;border:none">
                ACCEPT
              </button>
              <.link navigate={~p"/app/new?counter=#{d.id}"} class="hu-cond" style="cursor:pointer;flex:1;text-align:center;border:1px solid #252A3A;color:#F4F5F7;font-size:15px;border-radius:9px;padding:8px 0">
                COUNTER
              </.link>
              <button phx-click="decline" phx-value-id={d.id} class="hu-cond" style="cursor:pointer;flex:1;text-align:center;border:1px solid rgba(255,69,87,.4);color:#FF4557;font-size:15px;border-radius:9px;padding:8px 0;background:transparent">
                DECLINE
              </button>
            </div>

            <div :if={i_sent?(d, @current_user.id)} style="display:flex;gap:8px;margin-top:12px">
              <button phx-click="cancel" phx-value-id={d.id} class="hu-cond" style="cursor:pointer;flex:none;text-align:center;border:1px solid #252A3A;color:#8B91A7;font-size:13px;border-radius:9px;padding:6px 18px;background:transparent">
                CALL IT OFF
              </button>
            </div>

            <div :if={d.status in ~w(accepted drafting)} style="margin-top:12px">
              <.link navigate={~p"/app/draft/#{d.id}"} class="hu-cond" style="cursor:pointer;display:inline-block;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:15px;border-radius:999px;padding:8px 22px">
                ENTER ROOM →
              </.link>
            </div>
            <div :if={d.status == "drafted"} style="margin-top:12px">
              <.link navigate={~p"/app/live/#{d.id}"} class="hu-cond" style="cursor:pointer;display:inline-block;border:1px solid #FF4557;color:#FF4557;font-size:15px;border-radius:999px;padding:8px 22px">
                WATCH LIVE →
              </.link>
            </div>
          </div>
        </div>

        <div :if={@tab == "past"} style="display:flex;flex-direction:column;gap:10px">
          <p :if={@settled == [] and @dead == []} style="font-size:12px;color:#565D73;font-weight:600;padding:24px 0;text-align:center">
            No history yet.
          </p>

          <div :for={d <- @settled} style={"display:flex;align-items:center;gap:12px;border-radius:12px;border:1px solid #252A3A;border-left:3px solid #{res_tint(d, @current_user.id)};background:#12141D;padding:12px 14px"}>
            <span class="hu-cond" style={"font-size:19px;color:#{res_tint(d, @current_user.id)};width:24px"}>
              {res(d, @current_user.id)}
            </span>
            <.link navigate={~p"/app/results/#{d.id}"} style="cursor:pointer;display:flex;flex-direction:column;min-width:0;flex:1">
              <span style="font-weight:800;font-size:13.5px">vs {title(d, @current_user.id) |> String.replace_prefix("vs ", "")}</span>
              <span style="font-size:10.5px;color:#8B91A7;font-weight:600;margin-top:2px">{meta_line(d)}</span>
            </.link>
            <span :if={d.stake_coins > 0} style={"font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:14px;color:#{res_tint(d, @current_user.id)}"}>
              ◎ {swing(d, @current_user.id)}
            </span>
            <button
              :if={d.opponent_id != nil}
              phx-click="rematch"
              phx-value-id={d.id}
              style="cursor:pointer;flex:none;border:1px solid #252A3A;color:#8B91A7;font-size:10px;font-weight:900;letter-spacing:1px;border-radius:999px;padding:5px 12px;background:transparent"
            >
              REMATCH
            </button>
          </div>

          <span :if={@dead != []} style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#565D73;margin-top:6px">
            DECLINED &amp; CANCELLED
          </span>
          <div :for={d <- @dead} style="display:flex;align-items:center;gap:12px;border-radius:12px;border:1px solid #1A1E2B;background:#12141D;padding:12px 14px;opacity:.55">
            <div style="width:32px;height:32px;flex:none;border-radius:10px;background:rgba(139,145,167,.12);display:flex;align-items:center;justify-content:center;font-weight:800;font-size:12px;color:#8B91A7">
              {initials(title(d, @current_user.id))}
            </div>
            <div style="display:flex;flex-direction:column;min-width:0;flex:1">
              <span style="font-weight:800;font-size:13px">{title(d, @current_user.id)}</span>
              <span style="font-size:10.5px;color:#8B91A7;font-weight:600">{meta_line(d)}</span>
            </div>
            <span style="font-size:10px;font-weight:900;letter-spacing:1px;color:#565D73;border:1px solid #252A3A;border-radius:999px;padding:4px 11px">
              {String.upcase(d.status)}
            </span>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  # --- design tokens per status ----------------------------------------------

  defp tab_style(true),
    do:
      "cursor:pointer;font-size:12px;font-weight:800;letter-spacing:.5px;color:#0A0B10;background:var(--acc,#C8FF2E);border:1px solid var(--acc,#C8FF2E);border-radius:999px;padding:8px 18px;white-space:nowrap"

  defp tab_style(false),
    do:
      "cursor:pointer;font-size:12px;font-weight:800;letter-spacing:.5px;color:#8B91A7;background:transparent;border:1px solid #252A3A;border-radius:999px;padding:8px 18px;white-space:nowrap"

  defp group?(d), do: d.opponent_id == nil

  defp respond?(d, me) do
    d.status == "pending" and
      if group?(d),
        do: Enum.any?(d.participants, &(&1.user_id == me and &1.status == "invited")),
        else: d.opponent_id == me
  end

  defp i_sent?(d, me), do: d.status == "pending" and not respond?(d, me)

  defp title(d, me) do
    cond do
      group?(d) ->
        host = Enum.find(d.participants, &(&1.seat == 0))
        "#{(host && host.user.username) || "group"}'s #{length(d.participants)}-player match"

      d.challenger_id == me ->
        "vs #{(d.opponent && d.opponent.username) || "them"}"

      true ->
        "vs #{(d.challenger && d.challenger.username) || "them"}"
    end
  end

  defp meta_line(d) do
    emoji = %{"mlb" => "⚾️", "nfl" => "🏈"} |> Map.get(d.sport, "🏀")
    stake = if d.stake_coins > 0, do: " · ◎ #{d.stake_coins} stake", else: " · no stake"
    "#{emoji} #{String.upcase(d.sport)} · #{d.roster_size} slots#{stake}"
  end

  defp badge(d, me) do
    case d.status do
      "pending" -> if respond?(d, me), do: "YOUR CALL", else: "WAITING"
      "accepted" -> "DRAFT SET"
      "drafting" -> "DRAFTING"
      "drafted" -> "LIVE"
      other -> String.upcase(other)
    end
  end

  defp badge_ink(d, me) do
    case d.status do
      "pending" -> if respond?(d, me), do: "#FFB021", else: "#8B91A7"
      "accepted" -> "#C8FF2E"
      "drafting" -> "#C8FF2E"
      "drafted" -> "#FF4557"
      _ -> "#8B91A7"
    end
  end

  defp badge_bg(d, me) do
    case badge_ink(d, me) do
      "#FFB021" -> "rgba(255,176,33,.12)"
      "#C8FF2E" -> "rgba(200,255,46,.10)"
      "#FF4557" -> "rgba(255,69,87,.12)"
      _ -> "rgba(139,145,167,.10)"
    end
  end

  defp blink?(d), do: d.status in ~w(drafting drafted)

  defp card_border(%{status: "drafted"}), do: "rgba(255,69,87,.4)"
  defp card_border(%{status: s}) when s in ~w(accepted drafting), do: "rgba(200,255,46,.35)"
  defp card_border(_), do: "#252A3A"

  defp av_bg(d, me), do: if(respond?(d, me), do: "rgba(124,92,255,.18)", else: "rgba(200,255,46,.10)")
  defp av_ink(d, me), do: if(respond?(d, me), do: "#9F8BFF", else: "#C8FF2E")

  defp initials(name) do
    name |> String.replace_prefix("vs ", "") |> String.slice(0, 2) |> String.upcase()
  end

  defp res(d, me) do
    cond do
      d.winner_id == nil -> "T"
      d.winner_id == me -> "W"
      true -> "L"
    end
  end

  defp res_tint(d, me) do
    case res(d, me) do
      "W" -> "#C8FF2E"
      "L" -> "#FF4557"
      _ -> "#8B91A7"
    end
  end

  defp swing(d, me) do
    case res(d, me) do
      "W" -> "+#{d.stake_coins}"
      "L" -> "−#{d.stake_coins}"
      _ -> "0"
    end
  end
end
