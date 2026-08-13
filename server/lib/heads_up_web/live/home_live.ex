defmodule HeadsUpWeb.HomeLive do
  @moduledoc """
  The signed-in landing page on the web: your duels, and a way into whichever
  one wants you. Deliberately thin for now — Phase 0 exists to prove the draft
  room works in a browser, and this is the door to it.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Coins, Home}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(page_title: "Your duels")
    |> assign(summary: Home.summary(user))
    |> assign(coins: Coins.balance(user.id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mb-6 flex items-baseline justify-between">
        <h1 class="text-2xl font-black">Your duels</h1>
        <span class="text-sm font-bold text-[#C8FF2E]">{@coins} coins</span>
      </div>

      <.bucket title="Your move" duels={@summary.needs_response} empty="Nothing waiting on you." />
      <.bucket title="Ready to draft" duels={@summary.draft_ready} empty={nil} />
      <.bucket title="Waiting on them" duels={@summary.waiting_on_them} empty={nil} />
      <.bucket title="Scoring now" duels={@summary.awaiting} empty={nil} />

      <p class="mt-10 text-center text-xs text-[#565D73]">
        The web app is new. Creating challenges still lives in the phone app for now.
      </p>
    </Layouts.shell>
    """
  end

  attr :title, :string, required: true
  attr :duels, :list, required: true
  attr :empty, :string, default: nil

  defp bucket(assigns) do
    ~H"""
    <section :if={@duels != [] or @empty} class="mb-6">
      <h2 class="mb-2 text-[11px] font-black uppercase tracking-[0.18em] text-[#8B91A7]">{@title}</h2>

      <p :if={@duels == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-3 text-sm text-[#565D73]">
        {@empty}
      </p>

      <ul class="space-y-2">
        <li :for={duel <- @duels}>
          <.link
            navigate={~p"/app/draft/#{duel.id}"}
            class="flex items-center justify-between rounded-xl border border-[#252A3A] bg-[#12141D] px-4 py-3 hover:border-[#C8FF2E]/50"
          >
            <div>
              <p class="font-bold">{String.upcase(duel.sport)} · {duel.roster_size} slots</p>
              <p class="text-xs text-[#8B91A7]">{duel.status}</p>
            </div>
            <span class="text-xs font-black uppercase tracking-wide text-[#C8FF2E]">Open</span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end
end
