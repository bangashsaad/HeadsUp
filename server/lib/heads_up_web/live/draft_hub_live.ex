defmodule HeadsUpWeb.DraftHubLive do
  @moduledoc """
  The DRAFT tab with no draft on the clock — the design's "WAR ROOM'S DARK"
  state, dashed roster slots and all. When a draft IS waiting, this page just
  forwards you into its room.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Contests

  @impl true
  def mount(_params, _session, socket) do
    target =
      socket.assigns.current_user
      |> Contests.list_duels()
      |> Enum.find(&(&1.status in ~w(accepted drafting)))

    if target do
      {:ok, push_navigate(socket, to: ~p"/app/draft/#{target.id}")}
    else
      {:ok, assign(socket, page_title: "Draft")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="display:flex;flex-direction:column;align-items:center;gap:14px;padding:60px 20px;text-align:center;animation:huw-rise .3s ease">
        <div style="display:flex;gap:8px">
          <div :for={label <- ~w(G G F F FLX)} style="width:46px;height:46px;border-radius:13px;border:1px dashed #3A4157;display:flex;align-items:center;justify-content:center">
            <span style="font-size:10px;font-weight:800;color:#565D73">{label}</span>
          </div>
        </div>
        <span class="hu-cond" style="font-size:32px;line-height:1">WAR ROOM'S DARK<span style="color:var(--acc,#C8FF2E)">.</span></span>
        <span style="font-size:13px;color:#8B91A7;font-weight:600;max-width:360px">
          No draft on the clock. Accept a challenge — or send one — and the coin flip starts it.
        </span>
        <div style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center;margin-top:6px">
          <.link navigate={~p"/app/duels"} class="hu-cond" style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:17px;border-radius:999px;padding:12px 26px">
            VIEW CHALLENGES →
          </.link>
          <.link navigate={~p"/app/new"} class="hu-cond" style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:17px;border-radius:999px;padding:12px 26px">
            + NEW CHALLENGE
          </.link>
        </div>
      </div>
    </Layouts.shell>
    """
  end
end
