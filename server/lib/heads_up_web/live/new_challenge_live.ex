defmodule HeadsUpWeb.NewChallengeLive do
  @moduledoc """
  Set the terms, pick who answers for it — the web counterpart of the app's
  CreateChallenge screen, sending the identical payload to the same
  `Contests.create_challenge/2`.

  The option values are the app's, verbatim: four leagues (season-gated),
  5/7 rosters, 0/25/100 stakes, 15/30/60-second clocks, day slates for
  basketball and baseball, week slates for football, up to 3 rivals.
  `?counter=<duel_id>` seeds the form from a pending duel's terms and submits
  through `counter_challenge/3` instead — same as countering on the phone.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Coins, Contests, Social}
  alias HeadsUp.Sports.{Season, Slate}

  @leagues [
    %{key: "wnba", label: "🏀 WNBA"},
    %{key: "mlb", label: "⚾️ MLB"},
    %{key: "nfl", label: "🏈 NFL"},
    %{key: "nba", label: "🏀 NBA"}
  ]
  @rosters [5, 7]
  @stakes [0, 25, 100]
  @clocks [15, 30, 60]
  @max_rivals 3

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    playable =
      Season.statuses() |> Enum.filter(& &1.playable) |> MapSet.new(& &1.sport)

    counter = counter_duel(user, params["counter"])

    socket =
      socket
      |> assign(page_title: if(counter, do: "Counter offer", else: "New challenge"))
      |> assign(
        leagues: @leagues,
        rosters: @rosters,
        stakes: @stakes,
        clocks: @clocks,
        max_rivals: @max_rivals,
        playable: playable,
        friends: Social.list_friends(user),
        coins: Coins.balance(user.id),
        counter: counter,
        error: nil,
        submitting: false
      )
      |> seed_terms(counter, playable)
      |> load_slates()

    {:ok, socket}
  end

  defp counter_duel(_user, nil), do: nil

  defp counter_duel(user, id) do
    case Integer.parse(id) do
      {duel_id, ""} ->
        case Contests.get_duel(user, duel_id) do
          %{status: "pending"} = duel -> duel
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp seed_terms(socket, nil, playable) do
    league = Enum.find_value(@leagues, "wnba", &if(MapSet.member?(playable, &1.key), do: &1.key))
    assign(socket, league: league, roster: 5, stake: 0, clock: 30, rivals: [])
  end

  # A counter keeps everything about the duel except who's deciding: the
  # original challenger becomes the (fixed) opponent.
  defp seed_terms(socket, duel, _playable) do
    assign(socket,
      league: duel.sport,
      roster: duel.roster_size,
      stake: duel.stake_coins,
      clock: if(duel.pick_clock_seconds in @clocks, do: duel.pick_clock_seconds, else: 30),
      rivals: [duel.challenger_id]
    )
  end

  defp load_slates(socket) do
    league = socket.assigns.league

    {kind, slates} =
      if Slate.week_shaped?(league) do
        case Slate.weeks(league) do
          {:ok, weeks} -> {"week", weeks}
          _ -> {"week", []}
        end
      else
        case Slate.upcoming(league) do
          {:ok, days} -> {"day", Enum.filter(days, &(&1.upcoming > 0))}
          _ -> {"day", []}
        end
      end

    default =
      case slates do
        [first | _] -> slate_id(kind, first)
        [] -> nil
      end

    assign(socket, slate_kind: kind, slates: slates, slate: default)
  end

  defp slate_id("week", w), do: w.key
  defp slate_id("day", d), do: Date.to_iso8601(d.date)

  # --- events ---------------------------------------------------------------

  @impl true
  def handle_event("league", %{"key" => key}, socket) do
    if MapSet.member?(socket.assigns.playable, key) do
      {:noreply, socket |> assign(league: key) |> load_slates()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("roster", %{"n" => n}, socket),
    do: {:noreply, assign(socket, roster: String.to_integer(n))}

  def handle_event("stake", %{"n" => n}, socket),
    do: {:noreply, assign(socket, stake: String.to_integer(n))}

  def handle_event("clock", %{"n" => n}, socket),
    do: {:noreply, assign(socket, clock: String.to_integer(n))}

  def handle_event("slate", %{"id" => id}, socket), do: {:noreply, assign(socket, slate: id)}

  def handle_event("rival", %{"id" => id}, socket) do
    if socket.assigns.counter do
      {:noreply, socket}
    else
      id = String.to_integer(id)
      rivals = socket.assigns.rivals

      rivals =
        cond do
          id in rivals -> List.delete(rivals, id)
          length(rivals) >= @max_rivals -> rivals
          true -> rivals ++ [id]
        end

      {:noreply, assign(socket, rivals: rivals)}
    end
  end

  def handle_event("send", _params, socket) do
    %{league: league, roster: roster, stake: stake, clock: clock, rivals: rivals} = socket.assigns

    cond do
      rivals == [] ->
        {:noreply, assign(socket, error: "Pick at least one rival.")}

      stake > socket.assigns.coins ->
        {:noreply, assign(socket, error: "That stake is more than your wallet.")}

      true ->
        attrs =
          %{
            "sport" => league,
            "lineup_template" => "#{league}_#{roster}",
            "roster_size" => roster,
            "pick_clock_seconds" => clock,
            "stake_coins" => stake,
            "draft_starts_at" =>
              DateTime.utc_now() |> DateTime.add(15 * 60, :second) |> DateTime.to_iso8601()
          }
          |> put_who(rivals)
          |> put_slate(socket.assigns.slate_kind, socket.assigns.slate)

        submit(socket, attrs)
    end
  end

  defp put_who(attrs, [single]), do: Map.put(attrs, "opponent_id", single)
  defp put_who(attrs, many), do: Map.put(attrs, "opponent_ids", many)

  defp put_slate(attrs, _kind, nil), do: attrs
  defp put_slate(attrs, "week", id), do: Map.put(attrs, "slate_week", id)
  defp put_slate(attrs, "day", id), do: Map.put(attrs, "slate_date", id)

  defp submit(%{assigns: %{counter: %{} = original}} = socket, attrs) do
    case Contests.counter_challenge(socket.assigns.current_user, original.id, attrs) do
      {:ok, duel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Counter sent — their move now.")
         |> push_navigate(to: "/app/duels")
         |> then(fn s -> _ = duel; s end)}

      {:error, reason} ->
        {:noreply, assign(socket, error: humanize(reason))}
    end
  end

  defp submit(socket, attrs) do
    case Contests.create_challenge(socket.assigns.current_user, attrs) do
      {:ok, _duel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Challenge sent.")
         |> push_navigate(to: "/app/duels")}

      {:error, reason} ->
        {:noreply, assign(socket, error: humanize(reason))}
    end
  end

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(%Ecto.Changeset{}), do: "Those terms don't work — check them and try again."
  defp humanize(reason), do: "Couldn't send it (#{inspect(reason)})."

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mx-auto max-w-xl">
        <h1 class="text-2xl font-black">{if @counter, do: "Counter offer", else: "New challenge"}</h1>
        <p class="mt-1 text-sm text-[#8B91A7]">
          {if @counter,
            do: "You're editing #{@counter.challenger.username}'s terms — sending returns it to them.",
            else: "Set the terms first, then pick who has to answer for it."}
        </p>

        <p :if={@error} class="mt-4 rounded-lg border border-[#FF4557]/50 bg-[#FF4557]/10 px-3 py-2 text-sm text-[#FF4557]">
          {@error}
        </p>

        <.term_label>League</.term_label>
        <div class="flex flex-wrap gap-2">
          <button
            :for={l <- @leagues}
            phx-click="league"
            phx-value-key={l.key}
            disabled={not MapSet.member?(@playable, l.key)}
            class={seg(@league == l.key) <> " disabled:cursor-not-allowed disabled:opacity-30"}
          >
            {l.label}{if not MapSet.member?(@playable, l.key), do: " · off-season"}
          </button>
        </div>

        <.term_label>Roster size</.term_label>
        <div class="flex gap-2">
          <button :for={n <- @rosters} phx-click="roster" phx-value-n={n} class={seg(@roster == n)}>
            {n} slots
          </button>
        </div>

        <.term_label>Stake · ◎ coins ({@coins} in your wallet)</.term_label>
        <div class="flex gap-2">
          <button
            :for={n <- @stakes}
            phx-click="stake"
            phx-value-n={n}
            disabled={n > @coins}
            class={seg(@stake == n) <> " disabled:cursor-not-allowed disabled:opacity-30"}
          >
            {if n == 0, do: "Friendly", else: "◎ #{n}"}
          </button>
        </div>

        <.term_label>Pick clock</.term_label>
        <div class="flex gap-2">
          <button :for={n <- @clocks} phx-click="clock" phx-value-n={n} class={seg(@clock == n)}>
            {n} sec
          </button>
        </div>

        <div :if={@slates != []}>
          <.term_label>{if @slate_kind == "week", do: "Week — whose games count", else: "Slate — whose games count"}</.term_label>
          <div class="flex flex-wrap gap-2">
            <button
              :for={s <- Enum.take(@slates, 5)}
              phx-click="slate"
              phx-value-id={slate_id(@slate_kind, s)}
              class={seg(@slate == slate_id(@slate_kind, s))}
            >
              {slate_label(@slate_kind, s)} · {s.upcoming}
            </button>
          </div>
        </div>

        <div :if={!@counter}>
          <.term_label>Who answers for it (up to {@max_rivals})</.term_label>
          <p :if={@friends == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-5 text-center text-sm text-[#565D73]">
            No friends yet — add some from your profile first.
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              :for={f <- @friends}
              phx-click="rival"
              phx-value-id={f.id}
              class={seg(f.id in @rivals)}
            >
              {f.username}
            </button>
          </div>
        </div>

        <button
          phx-click="send"
          disabled={@submitting}
          class="mt-8 w-full rounded-xl bg-[#C8FF2E] px-4 py-4 text-base font-black uppercase tracking-wide text-[#0A0B10] hover:brightness-110 disabled:opacity-40"
        >
          {if @counter, do: "Send the counter", else: "Send it"}
        </button>
        <p class="mt-3 text-center text-xs text-[#565D73]">
          Everyone you call out gets a seat when they accept. Max 4 drafters.
        </p>
      </div>
    </Layouts.shell>
    """
  end

  slot :inner_block, required: true
  defp term_label(assigns) do
    ~H"""
    <p class="mb-2 mt-6 text-[11px] font-black uppercase tracking-[0.18em] text-[#8B91A7]">
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp seg(true),
    do: "rounded-lg bg-[#C8FF2E] px-3.5 py-2 text-xs font-black uppercase tracking-wide text-[#0A0B10]"

  defp seg(false),
    do:
      "rounded-lg border border-[#252A3A] bg-[#12141D] px-3.5 py-2 text-xs font-bold uppercase tracking-wide text-[#B9BECF] hover:border-[#C8FF2E]/40"

  defp slate_label("week", w), do: w.label

  defp slate_label("day", d) do
    today = Slate.today()

    cond do
      d.date == today -> "Tonight"
      d.date == Date.add(today, 1) -> "Tomorrow"
      true -> Calendar.strftime(d.date, "%a %b %-d")
    end
  end
end
