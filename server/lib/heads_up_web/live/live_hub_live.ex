defmodule HeadsUpWeb.LiveHubLive do
  @moduledoc """
  The LIVE tab with nothing on the line — the design's ghost 0.0 VS 0.0 board
  with "NOTHING ON THE LINE TONIGHT". With a live duel it forwards straight to
  the matchup.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Contests

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: HeadsUpWeb.Endpoint.subscribe(HeadsUp.Contests.Events.topic(socket.assigns.current_user.id))
    target =
      socket.assigns.current_user
      |> Contests.list_duels()
      |> Enum.find(&(&1.status == "drafted"))

    if target do
      {:ok, push_navigate(socket, to: ~p"/app/live/#{target.id}")}
    else
      {:ok, assign(socket, page_title: "Live")}
    end
  end

  # A duel just became drafted — jump into it.
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "duel_changed"}, socket) do
    target =
      socket.assigns.current_user
      |> Contests.list_duels()
      |> Enum.find(&(&1.status in ~w(drafted)))

    if target, do: {:noreply, push_navigate(socket, to: "/app/live/#{target.id}")}, else: {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="display:flex;flex-direction:column;align-items:center;gap:14px;padding:50px 20px;text-align:center;animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;gap:30px;opacity:.5">
          <div style="display:flex;flex-direction:column;align-items:center;gap:4px">
            <span style="font-size:11px;font-weight:900;letter-spacing:1.5px;color:#565D73">YOU</span>
            <span class="hu-cond" style="font-size:64px;line-height:.9;color:transparent;-webkit-text-stroke:1px #3A4157">0.0</span>
          </div>
          <span class="hu-black" style="font-size:20px;color:transparent;-webkit-text-stroke:1px #3A4157">VS</span>
          <div style="display:flex;flex-direction:column;align-items:center;gap:4px">
            <span style="font-size:11px;font-weight:900;letter-spacing:1.5px;color:#565D73">???</span>
            <span class="hu-cond" style="font-size:64px;line-height:.9;color:transparent;-webkit-text-stroke:1px #3A4157">0.0</span>
          </div>
        </div>
        <span class="hu-cond" style="font-size:32px;line-height:1">NOTHING ON THE LINE TONIGHT<span style="color:var(--acc,#C8FF2E)">.</span></span>
        <span style="font-size:13px;color:#8B91A7;font-weight:600;max-width:360px">
          Draft a duel and this board lights up with live box scores.
        </span>
        <div style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center;margin-top:6px">
          <.link navigate={~p"/app/new"} class="hu-cond" style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:17px;border-radius:999px;padding:12px 26px">
            START A DUEL →
          </.link>
          <.link navigate={~p"/app/games"} class="hu-cond" style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:17px;border-radius:999px;padding:12px 26px">
            TONIGHT'S GAMES
          </.link>
        </div>
      </div>
    </Layouts.shell>
    """
  end
end
