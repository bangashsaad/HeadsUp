defmodule HeadsUpWeb.Params do
  @moduledoc """
  Safe casts for client-supplied params. LiveView events and API params arrive
  as strings the client fully controls — `String.to_integer/1` on them turns a
  tampered payload into a crashed socket or a 500. `int/1` yields `-1` for
  anything that isn't a clean integer: a valid id that matches nothing, so
  downstream lookups fail closed instead of crashing.
  """

  def int(value) when is_integer(value), do: value

  def int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> -1
    end
  end

  def int(_), do: -1
end
