defmodule HeadsUpWeb.CoinsLive do
  @moduledoc """
  The wallet: balance hero + the ledger, the same receipt trail the phone's
  Coin History screen shows (labels verbatim). Rows tied to a duel link to
  its detail page. Read-only — coins can't be bought or cashed out, so there
  is nothing to do here but understand where they went.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Coins

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       page_title: "Coin wallet",
       balance: Coins.balance(user.id),
       entries: Coins.history(user.id)
     )}
  end

  # Read-only page; ignore anything tampered in.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- render -------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:16px;max-width:640px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;flex-direction:column">
          <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">COIN WALLET</span>
          <span style="font-size:11.5px;color:#8B91A7;font-weight:600">Every coin that moves shows up here — the full receipt trail.</span>
        </div>

        <div style="border-radius:16px;border:1px solid color-mix(in srgb,#FFB021 35%,transparent);background:linear-gradient(150deg,color-mix(in srgb,#FFB021 8%,#12141D),#12141D 60%);padding:20px">
          <span style="font-size:10px;font-weight:900;letter-spacing:2px;color:#565D73">COIN BALANCE</span>
          <div class="hu-cond" style="font-size:46px;color:#FFB021;line-height:1.1;margin-top:2px">◎ {fmt(@balance)}</div>
          <p style="font-size:11.5px;color:#8B91A7;font-weight:600;margin-top:6px">
            Free house coins — stake them on duels, win the pot. Can't be bought, can't be cashed out.
            Run dry and a daily comeback bonus tops you back up.
          </p>
        </div>

        <p :if={@entries == []} style="padding:26px;text-align:center;font-size:12px;color:#565D73;font-weight:600;border:1px dashed #252A3A;border-radius:16px">
          No movements yet — stake a duel and the receipts start here.
        </p>

        <div :if={@entries != []} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <.entry_row :for={e <- @entries} e={e} />
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :e, :map, required: true

  defp entry_row(%{e: e} = assigns) do
    assigns = assign(assigns, :duel_id, e.metadata["duel_id"])

    ~H"""
    <.link :if={@duel_id} navigate={"/app/duels/#{@duel_id}"} style={"cursor:pointer;#{row_style()}"}>
      <.entry_body e={@e} duel_id={@duel_id} />
    </.link>
    <div :if={!@duel_id} style={row_style()}>
      <.entry_body e={@e} duel_id={nil} />
    </div>
    """
  end

  defp row_style,
    do: "display:flex;align-items:center;gap:12px;padding:12px 16px;border-bottom:1px solid #14171F"

  attr :e, :map, required: true
  attr :duel_id, :any, required: true

  defp entry_body(assigns) do
    ~H"""
    <div style={"width:32px;height:32px;flex:none;border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:14px;background:#{if @e.amount > 0, do: "rgba(255,176,33,.12)", else: "#1A1E2B"}"}>
      {kind_icon(@e.kind)}
    </div>
    <div style="display:flex;flex-direction:column;min-width:0">
      <span style="font-size:12.5px;font-weight:800">{label(@e)}</span>
      <span style="font-size:10.5px;color:#565D73;font-weight:700">
        {if @duel_id, do: "Duel ##{@duel_id} · "}{when_label(@e.inserted_at)}
      </span>
    </div>
    <span class="hu-cond" style={"margin-left:auto;font-size:17px;color:#{if @e.amount > 0, do: "#FFB021", else: "#8B91A7"}"}>
      {if @e.amount > 0, do: "+", else: "−"}◎ {fmt(abs(@e.amount))}
    </span>
    """
  end

  # --- the phone's KIND_META, verbatim -------------------------------------

  defp label(%{kind: "grant", metadata: %{"reason" => "signup"}}), do: "Welcome bonus"
  defp label(%{kind: "grant", metadata: %{"reason" => "comeback"}}), do: "Comeback bonus"
  defp label(%{kind: "grant"}), do: "Bonus"
  defp label(%{kind: "stake"}), do: "Stake escrowed"
  defp label(%{kind: "refund"}), do: "Stake returned"
  defp label(%{kind: "payout"}), do: "Pot won"
  defp label(%{kind: "burn"}), do: "Burned"
  defp label(%{kind: "reversal"}), do: "Correction"
  defp label(%{kind: kind}), do: kind

  defp kind_icon("grant"), do: "🎁"
  defp kind_icon("stake"), do: "🔒"
  defp kind_icon("refund"), do: "↩️"
  defp kind_icon("payout"), do: "🏆"
  defp kind_icon("burn"), do: "🔥"
  defp kind_icon("reversal"), do: "⇄"
  defp kind_icon(_), do: "◎"

  defp when_label(dt), do: Calendar.strftime(dt, "%b %-d")

  defp fmt(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/(\d)(?=(\d{3})+$)/, "\\1,")

  defp fmt(n), do: to_string(n)
end
