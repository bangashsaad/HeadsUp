defmodule HeadsUp.Sports.Espn.Parse do
  @moduledoc """
  Pure decode/normalize helpers for the ESPN WNBA feed — no HTTP, no Ecto, no
  app state. Shared by the re-seed task (`Sports.Seeds`) and the live stats
  provider (`Settlement.Stats.WnbaEspn`) so the two agree byte-for-byte on how a
  name is keyed, how a position is coarsened, and how a boxscore stat is read.
  """

  @doc """
  Canonical match key for a player name. Lowercases, strips accents (NFD →
  drop combining marks), removes apostrophes/periods, and collapses any other
  punctuation to single spaces. `"A'ja Wilson"` and `"Amon-Ra St. Brown"` become
  stable keys that survive feed/slug spelling differences.

      iex> normalize_name("A'ja Wilson")
      "aja wilson"
  """
  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/['.]/u, "")
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def normalize_name(_), do: ""

  @doc """
  Coarsen any ESPN/legacy position string to the WNBA `"G" | "F" | "C"` scheme
  (ESPN only exposes Guard/Forward/Center for the WNBA). Unknown/blank → `"G"`.

      iex> normalize_position("Forward"); normalize_position("PF"); normalize_position(nil)
      "F"; "F"; "G"
  """
  @spec normalize_position(String.t() | nil) :: String.t()
  def normalize_position(pos) when is_binary(pos) do
    p = String.downcase(String.trim(pos))

    cond do
      p == "c" or String.contains?(p, "center") -> "C"
      p in ~w(f sf pf) or String.contains?(p, "forward") -> "F"
      p in ~w(g pg sg) or String.contains?(p, "guard") -> "G"
      true -> "G"
    end
  end

  def normalize_position(_), do: "G"

  @doc """
  Read one stat out of a boxscore athlete row by its column LABEL, using the
  row's `labels` header for the index. Returns the raw cell string or `nil` when
  the label is absent or the row is too short.

      iex> stat_value(["PTS", "REB"], ["21", "14"], "REB")
      "14"
  """
  @spec stat_value([String.t()], [String.t()], String.t()) :: String.t() | nil
  def stat_value(labels, stats, label)
      when is_list(labels) and is_list(stats) and is_binary(label) do
    case Enum.find_index(labels, &(&1 == label)) do
      nil -> nil
      idx -> Enum.at(stats, idx)
    end
  end

  def stat_value(_, _, _), do: nil

  @doc """
  The "made" count from an ESPN "made-attempted" cell like `"4-10"` (→ 4).
  Tolerates `"0-0"`, `"--"`, `""`, and `nil` (→ 0).
  """
  @spec made_from(String.t() | nil) :: integer()
  def made_from(cell) when is_binary(cell) do
    case String.split(cell, "-", parts: 2) do
      [made | _] -> to_int(made)
      _ -> 0
    end
  end

  def made_from(_), do: 0

  @doc "Tolerant integer read: ints/floats pass through, strings parse, junk → 0."
  @spec to_int(String.t() | number() | nil) :: integer()
  def to_int(n) when is_integer(n), do: n
  def to_int(n) when is_float(n), do: trunc(n)

  def to_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _rest} -> n
      :error -> 0
    end
  end

  def to_int(_), do: 0
end
