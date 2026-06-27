defmodule HeadsUp.Settlement.Window do
  @moduledoc """
  The frozen scoring window for a duel — the sport plus the time bounds whose
  games count. Built from the duel by the Settlement context and handed to the
  stats provider (which, in 5b, uses the bounds to query a real feed; the mock
  ignores them).
  """
  @enforce_keys [:sport, :opens_at, :closes_at]
  defstruct [:sport, :opens_at, :closes_at, :duel_id]

  @type t :: %__MODULE__{
          sport: String.t(),
          opens_at: DateTime.t(),
          closes_at: DateTime.t(),
          duel_id: integer() | nil
        }
end
