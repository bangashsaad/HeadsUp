defmodule HeadsUpWeb.CoinJSON do
  @doc "The wallet: current balance + recent movements (natural sign, newest first)."
  def index(%{balance: balance, entries: entries}) do
    %{
      balance: balance,
      entries:
        for e <- entries do
          %{
            id: e.id,
            amount: e.amount,
            kind: e.kind,
            duel_id: e.metadata["duel_id"],
            reason: e.metadata["reason"],
            inserted_at: e.inserted_at
          }
        end
    }
  end
end
