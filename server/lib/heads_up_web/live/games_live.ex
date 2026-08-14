defmodule HeadsUpWeb.GamesLive do
  @moduledoc """
  The scoreboard: real games and the player pool, same two lenses as the
  app's Games tab. Reuses `Sports.Schedule` and `Sports.list_players`
  directly — no new data paths, so the phone and the browser can't disagree
  about tonight's slate.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Sports
  alias HeadsUp.Sports.Schedule

  @sports ~w(wnba mlb nfl)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Games", sport: "wnba", mode: "games", query: "")
     |> load()}
  end

  defp load(%{assigns: %{mode: "games", sport: sport}} = socket) do
    games =
      case Schedule.upcoming(sport) do
        {:ok, list} -> list
        _ -> []
      end

    assign(socket, games: games, players: [])
  end

  defp load(%{assigns: %{mode: "players", sport: sport, query: q}} = socket) do
    assign(socket, players: Sports.list_players(sport, q: q, limit: 60), games: [])
  end

  @impl true
  def handle_event("sport", %{"key" => key}, socket) when key in @sports do
    {:noreply, socket |> assign(sport: key) |> load()}
  end

  def handle_event("mode", %{"m" => m}, socket) when m in ~w(games players) do
    {:noreply, socket |> assign(mode: m) |> load()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(query: q) |> load()}
  end

  def handle_event(_other, _params, socket), do: {:noreply, socket}

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mb-4 flex items-center justify-between">
        <h1 class="hu-cond text-3xl tracking-wide">SCOREBOARD</h1>
        <div class="flex gap-1 rounded-lg border border-[#1A1E2B] bg-[#0D0F16] p-0.5">
          <button
            :for={{m, label} <- [{"games", "Games"}, {"players", "Players"}]}
            phx-click="mode"
            phx-value-m={m}
            class={[
              "rounded-md px-3 py-1.5 text-[11px] font-black uppercase tracking-wide",
              if(@mode == m, do: "bg-[#C8FF2E] text-[#0A0B10]", else: "text-[#8B91A7]")
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <div class="mb-4 flex gap-2">
        <button
          :for={s <- ["wnba", "mlb", "nfl"]}
          phx-click="sport"
          phx-value-key={s}
          class={[
            "rounded-lg px-3.5 py-2 text-xs font-black uppercase tracking-wide",
            if(@sport == s,
              do: "bg-[#C8FF2E] text-[#0A0B10]",
              else: "border border-[#252A3A] bg-[#12141D] text-[#B9BECF]"
            )
          ]}
        >
          {String.upcase(s)}
        </button>
      </div>

      <div :if={@mode == "games"}>
        <p :if={@games == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-10 text-center text-sm text-[#565D73]">
          Quiet night — no games on the slate.
        </p>
        <ul class="space-y-2">
          <li :for={g <- @games} class="flex items-center justify-between rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-3">
            <div class="flex items-center gap-3">
              <span class="text-sm font-black">{g.away && g.away.abbrev} @ {g.home && g.home.abbrev}</span>
              <span :if={g.state == "in"} class="flex items-center gap-1 text-[10px] font-black uppercase text-[#FF4557]">
                <span class="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-[#FF4557]"></span> {g.status}
              </span>
              <span :if={g.state == "post"} class="text-[10px] font-black uppercase text-[#8B91A7]">Final</span>
              <span :if={g.state == "pre"} class="text-[10px] font-bold uppercase text-[#565D73]">{g.status}</span>
            </div>
            <span :if={g.state != "pre"} class="text-sm font-black tabular-nums">
              {g.away && g.away.score}–{g.home && g.home.score}
            </span>
          </li>
        </ul>
      </div>

      <div :if={@mode == "players"}>
        <form id="pool-search" phx-change="search" class="mb-3">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="Search the pool"
            autocomplete="off"
            class="w-full rounded-xl border border-[#252A3A] bg-[#12141D] px-4 py-2.5 text-sm outline-none focus:border-[#C8FF2E]/60"
          />
        </form>
        <ul class="space-y-1.5">
          <li :for={p <- @players} class="flex items-center gap-3 rounded-xl border border-[#1A1E2B] bg-[#12141D] px-3 py-2">
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-bold">{p.name}</p>
              <p class="text-[11px] text-[#8B91A7]">{p.position} · {p.team}</p>
            </div>
            <span class="text-sm font-black text-[#C8FF2E]">{proj(p.projection)}</span>
          </li>
        </ul>
      </div>
    </Layouts.shell>
    """
  end

  defp proj(nil), do: "—"
  defp proj(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp proj(n), do: to_string(n)
end
