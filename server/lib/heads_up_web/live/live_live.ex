defmodule HeadsUpWeb.LiveLive do
  @moduledoc """
  The live matchup in the design's exact clothes: the radial-glow scoreboard
  hero with the lead delta and momentum bar, the two FIVE columns with player
  photos and condensed point totals, and the sticky trash-talk rail.

  Scores refresh on the same 15-second cadence the phone polls at; chat is
  push over `"duel_chat:<id>"`, so a jab from either platform lands instantly.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Contests, Settlement}

  @tick_ms 15_000

  @impl true
  def mount(%{"id" => id_str}, _session, socket) do
    user = socket.assigns.current_user

    with {duel_id, ""} <- Integer.parse(id_str),
         %{} = duel <- Contests.get_duel(user, duel_id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(HeadsUp.PubSub, "duel_chat:#{duel_id}")
        :timer.send_interval(@tick_ms, self(), :tick)
      end

      chat =
        case Contests.list_messages(user, duel_id) do
          {:ok, messages} -> messages
          _ -> []
        end

      {:ok,
       socket
       |> assign(page_title: "Live", duel_id: duel_id, duel: duel, chat: chat, draft: "")
       |> load_live()}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "That duel isn't yours.") |> redirect(to: "/app")}
    end
  end

  defp load_live(socket) do
    case Settlement.live_result(socket.assigns.duel_id) do
      {:ok, live} ->
        assign(socket, live: HeadsUpWeb.LiveJSON.show(%{live: live, current_user_id: socket.assigns.current_user.id}))

      {:error, _} ->
        assign(socket, live: nil)
    end
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, load_live(socket)}
  def handle_info({:duel_message, message}, socket), do: {:noreply, update(socket, :chat, &(&1 ++ [message]))}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("draft", %{"body" => body}, socket), do: {:noreply, assign(socket, draft: body)}

  def handle_event("send", %{"body" => body}, socket) do
    case Contests.post_message(socket.assigns.current_user, socket.assigns.duel_id, body) do
      {:ok, _} -> {:noreply, assign(socket, draft: "")}
      {:error, %Ecto.Changeset{}} -> {:noreply, put_flash(socket, :error, "Keep it under 280.")}
      {:error, _} -> {:noreply, socket}
    end
  end

  # --- render (the design's markup) -------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, sides: sides(assigns))

    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-wrap:wrap;gap:24px;max-width:1200px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="flex:1;min-width:min(460px,100%);display:flex;flex-direction:column;gap:18px">
          <%= if @sides do %>
            <.hero sides={@sides} duel={@duel} live={@live} />
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px">
              <.five side={elem(@sides, 0)} mine={true} />
              <.five side={elem(@sides, 1)} mine={false} />
            </div>
          <% else %>
            <div style="border-radius:18px;border:1px solid #252A3A;background:#12141D;padding:40px;text-align:center">
              <p class="hu-cond" style="font-size:26px">THIS ONE'S DECIDED</p>
              <.link navigate={~p"/app/results/#{@duel_id}"} style="font-size:12px;font-weight:900;letter-spacing:1px;color:var(--acc,#C8FF2E)">
                SEE THE FINAL RESULT →
              </.link>
            </div>
          <% end %>
        </div>

        <%!-- chat rail --%>
        <div style="width:310px;flex:none;display:flex;flex-direction:column;border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden;max-height:calc(100vh - 110px);position:sticky;top:70px;box-sizing:border-box">
          <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between;flex:none">
            <span class="hu-cond" style="font-size:15px;letter-spacing:1px">TRASH TALK</span>
            <span style="font-size:10px;font-weight:800;letter-spacing:1px;color:#565D73">{chat_names(@duel, @current_user.id)}</span>
          </div>
          <div id="chat-thread" phx-hook="ScrollToEnd" style="flex:1;overflow:auto;padding:14px;display:flex;flex-direction:column;gap:9px;min-height:180px">
            <p :if={@chat == []} style="font-size:11px;color:#565D73;font-weight:600;text-align:center;padding:20px 0">
              Say something. Scoreboard talk is free.
            </p>
            <div :for={m <- @chat} style={"display:flex;flex-direction:column;gap:2px;align-items:#{if m.user_id == @current_user.id, do: "flex-end", else: "flex-start"}"}>
              <span style={"font-size:9.5px;font-weight:900;letter-spacing:1px;color:#{if m.user_id == @current_user.id, do: "#C8FF2E", else: "#9F8BFF"}"}>
                {if m.user_id == @current_user.id, do: "YOU", else: String.upcase(m.username)}
              </span>
              <span style={"font-size:13px;line-height:1.45;color:#E6E8F0;background:#{if m.user_id == @current_user.id, do: "rgba(200,255,46,.08)", else: "rgba(124,92,255,.12)"};border:1px solid #{if m.user_id == @current_user.id, do: "rgba(200,255,46,.35)", else: "rgba(124,92,255,.4)"};border-radius:12px;padding:8px 12px;max-width:220px"}>
                {m.body}
              </span>
            </div>
          </div>
          <form phx-submit="send" phx-change="draft" id="chat-form" style="flex:none;padding:12px;border-top:1px solid #1A1E2B;display:flex;gap:8px">
            <input
              type="text"
              name="body"
              value={@draft}
              maxlength="280"
              autocomplete="off"
              placeholder="Talk your talk…"
              style="flex:1;min-width:0;background:#0D0F16;border:1px solid #252A3A;border-radius:999px;padding:10px 15px;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:13px;outline:none"
            />
            <button type="submit" style="cursor:pointer;flex:none;width:38px;height:38px;border-radius:999px;background:var(--acc,#C8FF2E);display:flex;align-items:center;justify-content:center;border:none">
              <span style="width:15px;height:15px;background:#0A0B10;-webkit-mask:url('/icons/245274a1.svg') center/contain no-repeat;mask:url('/icons/245274a1.svg') center/contain no-repeat">
              </span>
            </button>
          </form>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :sides, :any, required: true
  attr :duel, :map, required: true
  attr :live, :map, required: true

  defp hero(assigns) do
    {me, them} = assigns.sides
    lead = Float.round((me.total || 0.0) - (them.total || 0.0), 1)
    assigns = assign(assigns, me: me, them: them, lead: lead)

    ~H"""
    <div style="position:relative;overflow:hidden;border-radius:18px;border:1px solid #252A3A;background:radial-gradient(600px 280px at 50% -20%,rgba(124,92,255,.22),transparent 65%),#12141D;padding:22px 24px">
      <div style="display:flex;align-items:center;justify-content:space-between">
        <span style="display:inline-flex;align-items:center;gap:7px;background:rgba(255,69,87,.15);border:1px solid #FF4557;border-radius:999px;padding:4px 11px">
          <span class="huw-blink" style="width:6px;height:6px;border-radius:3px;background:#FF4557"></span>
          <span style="color:#FF4557;font-size:11px;font-weight:900;letter-spacing:1.5px">LIVE</span>
        </span>
        <span style="font-size:11px;font-weight:800;color:#8B91A7;letter-spacing:1px">
          {String.upcase(@duel.sport)} · {@duel.roster_size} SLOTS · RIVALRY GAME
        </span>
      </div>
      <div style="display:flex;align-items:center;justify-content:center;gap:clamp(20px,4vw,52px);margin-top:14px">
        <div style="display:flex;flex-direction:column;align-items:center;gap:3px">
          <span style="font-size:12px;font-weight:900;letter-spacing:1.5px;color:var(--acc,#C8FF2E)">
            {String.upcase(@current_user.username)}
          </span>
          <span class="hu-cond" style="font-size:clamp(46px,6.5vw,78px);line-height:.9">{pts(@me.total)}</span>
        </div>
        <div style="display:flex;flex-direction:column;align-items:center;gap:5px">
          <span class="hu-black" style="font-size:22px;color:#565D73">VS</span>
          <span style={"font-size:11px;font-weight:800;color:#{if @lead >= 0, do: "var(--acc,#C8FF2E)", else: "#FF4557"}"}>
            {if @lead >= 0, do: "+#{@lead}", else: "#{@lead}"}
          </span>
        </div>
        <div style="display:flex;flex-direction:column;align-items:center;gap:3px">
          <span style="font-size:12px;font-weight:900;letter-spacing:1.5px;color:#8B91A7">
            {String.upcase(@them.user.username)}
          </span>
          <span class="hu-cond" style="font-size:clamp(46px,6.5vw,78px);line-height:.9;color:#8B91A7">{pts(@them.total)}</span>
        </div>
      </div>
      <div style="max-width:520px;margin:16px auto 0">
        <div style="height:7px;border-radius:4px;background:rgba(124,92,255,.35);overflow:hidden">
          <div style={"width:#{momentum(@me, @them)}%;height:100%;background:var(--acc,#C8FF2E)"}></div>
        </div>
        <div style="display:flex;justify-content:space-between;margin-top:7px">
          <span style="font-size:10px;font-weight:900;letter-spacing:.5px;color:#8B91A7">{lead_line(@lead, @them)}</span>
          <span style="font-size:10px;font-weight:800;color:#565D73">{games_line(@live, @duel)}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :side, :map, required: true
  attr :mine, :boolean, required: true

  defp five(assigns) do
    ~H"""
    <div style={"border-radius:16px;border:1px solid #{if @mine, do: "color-mix(in srgb,var(--acc,#C8FF2E) 35%,transparent)", else: "#252A3A"};background:#12141D;overflow:hidden"}>
      <div style="padding:11px 16px;border-bottom:1px solid #1A1E2B;display:flex;justify-content:space-between">
        <span style={"font-size:11px;font-weight:900;letter-spacing:1.5px;color:#{if @mine, do: "var(--acc,#C8FF2E)", else: "#8B91A7"}"}>
          {if @mine, do: "YOUR #{count_word(length(@side.players))}", else: "#{String.upcase(@side.user.username)}'S #{count_word(length(@side.players))}"}
        </span>
        <span style="font-size:11px;font-weight:800;color:#565D73">{pts(@side.total)}</span>
      </div>
      <div :for={p <- @side.players} style="display:flex;align-items:center;gap:11px;padding:8px 16px;border-bottom:1px solid #14171F">
        <img
          :if={p.headshot_url}
          src={p.headshot_url}
          style="width:34px;height:34px;flex:none;border-radius:10px;object-fit:cover;object-position:top;background:#1A1E2B"
          alt=""
          loading="lazy"
        />
        <div
          :if={!p.headshot_url}
          style="width:34px;height:34px;flex:none;border-radius:10px;background:#1A1E2B;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:11px;color:#8B91A7"
        >
          {initials(p.name)}
        </div>
        <div style="display:flex;flex-direction:column;min-width:0">
          <span style="font-weight:700;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{p.name || "—"}</span>
          <span style="font-size:10.5px;color:#565D73;font-weight:700">
            {p.line || "no line yet"}{if p.game && p.game.state == "in", do: " · #{p.game.detail}"}
          </span>
        </div>
        <span class="hu-cond" style={"margin-left:auto;font-size:21px;color:#{pts_color(p)}"}>{pts(p.points)}</span>
      </div>
    </div>
    """
  end

  # --- helpers ---------------------------------------------------------------

  defp sides(%{live: nil}), do: nil

  defp sides(%{live: live}) do
    case live.sides do
      [a, b | _] -> if a.is_me, do: {a, b}, else: {b, a}
      _ -> nil
    end
  end

  defp pts(nil), do: "0.0"
  defp pts(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp pts(n), do: to_string(n)

  defp pts_color(%{game: %{state: "in"}}), do: "#F4F5F7"
  defp pts_color(%{points: p}) when is_number(p) and p > 0, do: "#F4F5F7"
  defp pts_color(_), do: "#565D73"

  defp momentum(me, them) do
    total = (me.total || 0) + (them.total || 0)
    if total > 0, do: round((me.total || 0) / total * 100), else: 50
  end

  defp lead_line(lead, them) do
    name = String.upcase(them.user.username)

    cond do
      lead > 0 -> "YOU LEAD BY #{lead}"
      lead < 0 -> "#{name} LEADS BY #{abs(lead)}"
      true -> "DEAD EVEN"
    end
  end

  defp games_line(live, duel) do
    base =
      case live.games do
        %{final: f, live: l, upcoming: u} -> "#{f} FINAL · #{l} LIVE · #{u} TO TIP"
        _ -> ""
      end

    pot = duel.stake_coins * 2
    if pot > 0, do: base <> " · ◎ #{pot} POT", else: base
  end

  defp initials(nil), do: "?"
  defp initials(name), do: name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join()

  defp chat_names(duel, me) do
    other =
      cond do
        duel.opponent_id == nil -> "THE TABLE"
        duel.challenger_id == me -> String.upcase((duel.opponent && duel.opponent.username) || "THEM")
        true -> String.upcase((duel.challenger && duel.challenger.username) || "THEM")
      end

    "YOU + #{other}"
  end

  defp count_word(5), do: "FIVE"
  defp count_word(7), do: "SEVEN"
  defp count_word(n), do: to_string(n)
end
