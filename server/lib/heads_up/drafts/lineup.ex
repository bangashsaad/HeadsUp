defmodule HeadsUp.Drafts.Lineup do
  @moduledoc """
  Standard preset lineup templates per sport — the positional roster structure
  a duel is drafted into. Pure module (no Ecto), mirroring `Contests.Scoring`.

  A template is keyed by a `"<sport>_<preset>"` string (e.g. `"nba_standard"`)
  and resolves to an ORDERED list of slots. Each slot is a map:

      %{key: "RB2", label: "RB", eligible: ["RB"]}

  - `key` is unique within the template (so two RB slots are "RB1"/"RB2") and is
    what `draft_picks.slot` stores — making a roster self-describing for replay.
  - `label` is the human position shown in the UI.
  - `eligible` lists the player positions that may fill the slot (FLEX/UTIL/G/F/
    CI/MI expand to several positions).

  The ordered slot list IS the canonical draft-board layout, and its length is
  the per-team pick count (== `duels.roster_size`). A team's current roster is
  passed as a list of already-FILLED slot keys; `can_fill?/3` returns the first
  open slot (in template order) a player's position is eligible for. Both the
  manual-pick validation and the position-aware auto-pick use that one function.
  """

  # --- eligibility groups -------------------------------------------------
  @nfl_flex ~w(RB WR TE)
  @nba_g ~w(PG SG)
  @nba_f ~w(SF PF)
  # WNBA uses a COARSE G/F/C scheme because the ESPN feed only exposes
  # Guard/Forward/Center. Legacy granular codes (PG/SG/SF/PF) stay in the
  # eligibility lists so any not-yet-reseeded rows remain draftable.
  @wnba_g ~w(G PG SG)
  @wnba_f ~w(F SF PF)
  @wnba_c ~w(C)
  @wnba_util ~w(G F C PG SG SF PF)
  @mlb_hitter ~w(C 1B 2B 3B SS OF DH)
  @mlb_if ~w(1B 2B 3B SS)
  @mlb_ci ~w(1B 3B)
  @mlb_mi ~w(2B SS)

  # --- preset templates ---------------------------------------------------
  # NBA and WNBA share identical positional structure (see Scoring.@wnba).
  @nba_quick [
    %{key: "G1", label: "G", eligible: @nba_g},
    %{key: "F1", label: "F", eligible: @nba_f},
    %{key: "C1", label: "C", eligible: ["C"]}
  ]
  @nba_standard [
    %{key: "PG1", label: "PG", eligible: ["PG"]},
    %{key: "SG1", label: "SG", eligible: ["SG"]},
    %{key: "SF1", label: "SF", eligible: ["SF"]},
    %{key: "PF1", label: "PF", eligible: ["PF"]},
    %{key: "C1", label: "C", eligible: ["C"]}
  ]

  # WNBA coarse G/F/C templates (the live ESPN feed only emits G/F/C). The
  # UTIL slot accepts any position so a 1v1 can never deadlock on the league's
  # scarce centers.
  @wnba_quick [
    %{key: "G1", label: "G", eligible: @wnba_g},
    %{key: "F1", label: "F", eligible: @wnba_f},
    %{key: "C1", label: "C", eligible: @wnba_c}
  ]
  @wnba_standard [
    %{key: "G1", label: "G", eligible: @wnba_g},
    %{key: "G2", label: "G", eligible: @wnba_g},
    %{key: "F1", label: "F", eligible: @wnba_f},
    %{key: "F2", label: "F", eligible: @wnba_f},
    %{key: "C1", label: "C", eligible: @wnba_c},
    %{key: "UTIL1", label: "UTIL", eligible: @wnba_util}
  ]

  # --- canonical roster shapes (challenge-screen spec) --------------------
  # Sizes 5 and 7, each ending in a single FLEX. Basketball is GUARD/FORWARD
  # (centers ride the FLEX — the league only has ~24 of them); baseball is
  # PITCHER/INFIELD/OUTFIELD with catchers counted as infield, since these
  # shapes have no dedicated C slot.
  @bball_flex @wnba_util
  @mlb_infield ~w(C 1B 2B 3B SS)
  @mlb_pitcher ~w(SP RP)

  @bball_5 [
    %{key: "G1", label: "GUARD", eligible: @wnba_g},
    %{key: "G2", label: "GUARD", eligible: @wnba_g},
    %{key: "F1", label: "FORWARD", eligible: @wnba_f},
    %{key: "F2", label: "FORWARD", eligible: @wnba_f},
    %{key: "FLEX1", label: "FLEX", eligible: @bball_flex}
  ]

  @bball_7 [
    %{key: "G1", label: "GUARD", eligible: @wnba_g},
    %{key: "G2", label: "GUARD", eligible: @wnba_g},
    %{key: "G3", label: "GUARD", eligible: @wnba_g},
    %{key: "F1", label: "FORWARD", eligible: @wnba_f},
    %{key: "F2", label: "FORWARD", eligible: @wnba_f},
    %{key: "F3", label: "FORWARD", eligible: @wnba_f},
    %{key: "FLEX1", label: "FLEX", eligible: @bball_flex}
  ]

  @mlb_5 [
    %{key: "P1", label: "PITCHER", eligible: @mlb_pitcher},
    %{key: "IF1", label: "INFIELD", eligible: @mlb_infield},
    %{key: "IF2", label: "INFIELD", eligible: @mlb_infield},
    %{key: "OF1", label: "OUTFIELD", eligible: ["OF"]},
    %{key: "FLEX1", label: "FLEX", eligible: @mlb_hitter}
  ]

  # Football keeps only the four positions our scoring chart can reward, so
  # every shape is QB + touches + a FLEX. This mirrors a standard DFS roster.
  @nfl_5 [
    %{key: "QB1", label: "QB", eligible: ["QB"]},
    %{key: "RB1", label: "RB", eligible: ["RB"]},
    %{key: "WR1", label: "WR", eligible: ["WR"]},
    %{key: "WR2", label: "WR", eligible: ["WR"]},
    %{key: "FLEX1", label: "FLEX", eligible: @nfl_flex}
  ]

  @nfl_7 [
    %{key: "QB1", label: "QB", eligible: ["QB"]},
    %{key: "RB1", label: "RB", eligible: ["RB"]},
    %{key: "RB2", label: "RB", eligible: ["RB"]},
    %{key: "WR1", label: "WR", eligible: ["WR"]},
    %{key: "WR2", label: "WR", eligible: ["WR"]},
    %{key: "TE1", label: "TE", eligible: ["TE"]},
    %{key: "FLEX1", label: "FLEX", eligible: @nfl_flex}
  ]

  @mlb_7 [
    %{key: "P1", label: "PITCHER", eligible: @mlb_pitcher},
    %{key: "P2", label: "PITCHER", eligible: @mlb_pitcher},
    %{key: "IF1", label: "INFIELD", eligible: @mlb_infield},
    %{key: "IF2", label: "INFIELD", eligible: @mlb_infield},
    %{key: "OF1", label: "OUTFIELD", eligible: ["OF"]},
    %{key: "OF2", label: "OUTFIELD", eligible: ["OF"]},
    %{key: "FLEX1", label: "FLEX", eligible: @mlb_hitter}
  ]

  # Baseball's real sizes (Saad's call, 2026-08-16): the coarse 5/7 shapes
  # stay registered for duels that already exist, but new challenges offer
  # these two. The 6 is one ace + five bats; the 9 is "draft the diamond" —
  # a true position at every spot, and only ONE required pitcher so a
  # two-game slate stays draftable. DH-only players (hi, Shohei) fit the 6's
  # UTIL; the 9 has no seat for them on purpose.
  @mlb_6 [
    %{key: "P1", label: "PITCHER", eligible: @mlb_pitcher},
    %{key: "IF1", label: "INFIELD", eligible: @mlb_infield},
    %{key: "IF2", label: "INFIELD", eligible: @mlb_infield},
    %{key: "OF1", label: "OUTFIELD", eligible: ["OF"]},
    %{key: "OF2", label: "OUTFIELD", eligible: ["OF"]},
    %{key: "UTIL1", label: "UTIL", eligible: @mlb_hitter}
  ]

  @mlb_9 [
    %{key: "P1", label: "PITCHER", eligible: @mlb_pitcher},
    %{key: "C1", label: "C", eligible: ["C"]},
    %{key: "B1", label: "1B", eligible: ["1B"]},
    %{key: "B2", label: "2B", eligible: ["2B"]},
    %{key: "B3", label: "3B", eligible: ["3B"]},
    %{key: "SS1", label: "SS", eligible: ["SS"]},
    %{key: "OF1", label: "OF", eligible: ["OF"]},
    %{key: "OF2", label: "OF", eligible: ["OF"]},
    %{key: "OF3", label: "OF", eligible: ["OF"]}
  ]

  @templates %{
    "nfl_5" => @nfl_5,
    "nfl_7" => @nfl_7,
    "wnba_5" => @bball_5,
    "wnba_7" => @bball_7,
    "nba_5" => @bball_5,
    "nba_7" => @bball_7,
    "mlb_5" => @mlb_5,
    "mlb_6" => @mlb_6,
    "mlb_7" => @mlb_7,
    "mlb_9" => @mlb_9,
    "nfl_quick" => [
      %{key: "QB1", label: "QB", eligible: ["QB"]},
      %{key: "RB1", label: "RB", eligible: ["RB"]},
      %{key: "WR1", label: "WR", eligible: ["WR"]},
      %{key: "FLEX1", label: "FLEX", eligible: @nfl_flex}
    ],
    "nfl_standard" => [
      %{key: "QB1", label: "QB", eligible: ["QB"]},
      %{key: "RB1", label: "RB", eligible: ["RB"]},
      %{key: "RB2", label: "RB", eligible: ["RB"]},
      %{key: "WR1", label: "WR", eligible: ["WR"]},
      %{key: "WR2", label: "WR", eligible: ["WR"]},
      %{key: "TE1", label: "TE", eligible: ["TE"]},
      %{key: "FLEX1", label: "FLEX", eligible: @nfl_flex}
    ],
    "nba_quick" => @nba_quick,
    "nba_standard" => @nba_standard,
    "wnba_quick" => @wnba_quick,
    "wnba_standard" => @wnba_standard,
    "mlb_quick" => [
      %{key: "SP1", label: "SP", eligible: ["SP"]},
      %{key: "C1", label: "C", eligible: ["C"]},
      %{key: "IF1", label: "IF", eligible: @mlb_if},
      %{key: "OF1", label: "OF", eligible: ["OF"]},
      %{key: "UTIL1", label: "UTIL", eligible: @mlb_hitter}
    ],
    "mlb_standard" => [
      %{key: "SP1", label: "SP", eligible: ["SP"]},
      %{key: "RP1", label: "RP", eligible: ["RP"]},
      %{key: "C1", label: "C", eligible: ["C"]},
      %{key: "CI1", label: "CI", eligible: @mlb_ci},
      %{key: "MI1", label: "MI", eligible: @mlb_mi},
      %{key: "OF1", label: "OF", eligible: ["OF"]},
      %{key: "UTIL1", label: "UTIL", eligible: @mlb_hitter}
    ]
  }

  @type slot :: %{key: String.t(), label: String.t(), eligible: [String.t()]}

  @doc "All known template keys, e.g. `[\"nfl_quick\", \"nba_standard\", ...]`."
  @spec templates() :: [String.t()]
  def templates, do: Map.keys(@templates)

  @doc """
  The default template for a sport: the canonical 5-slot shape where one
  exists, else the legacy `_standard` preset.
  """
  @spec default_template(String.t()) :: String.t()
  def default_template(sport) do
    case sizes_for(sport) do
      [n | _] -> "#{sport}_#{n}"
      [] -> "#{sport}_standard"
    end
  end

  @doc """
  Canonical roster sizes OFFERED for a sport, smallest first. Baseball runs
  6/9 (one ace + five bats, or the whole diamond); everyone else 5/7. This is
  deliberately not derived from the registry — mlb_5/mlb_7 stay registered so
  duels that already carry them keep drafting, but new challenges don't offer
  them.
  """
  @spec sizes_for(String.t()) :: [pos_integer()]
  def sizes_for("mlb"), do: [6, 9]

  def sizes_for(sport) do
    for n <- [5, 7], Map.has_key?(@templates, "#{sport}_#{n}"), do: n
  end

  @doc "Template keys available for a sport (e.g. `\"nba\"` -> the two nba_* keys)."
  @spec templates_for(String.t()) :: [String.t()]
  def templates_for(sport) do
    @templates |> Map.keys() |> Enum.filter(&String.starts_with?(&1, sport <> "_")) |> Enum.sort()
  end

  @doc "True if `template` is a known preset key."
  @spec valid?(String.t()) :: boolean()
  def valid?(template), do: Map.has_key?(@templates, template)

  @doc "Ordered slot list for a template key, or `[]` for an unknown key."
  @spec slots(String.t()) :: [slot]
  def slots(template), do: Map.get(@templates, template, [])

  @doc "Number of slots in a template == per-team pick count == roster_size. 0 if unknown."
  @spec slot_count(String.t()) :: non_neg_integer()
  def slot_count(template), do: template |> slots() |> length()

  @doc """
  The first OPEN slot (in template order) whose `:eligible` includes `position`.

  `filled` is a list of already-filled slot keys for the team. Returns
  `{:ok, slot_key}` (the slot the player should occupy) or `:error` when no
  open slot fits — which both rejects an illegal manual pick and tells the
  auto-pick to skip this player and try the next-ranked one.
  """
  @spec can_fill?([slot], [String.t()], String.t()) :: {:ok, String.t()} | :error
  def can_fill?(slots, filled, position) do
    slots
    |> Enum.reject(fn s -> s.key in filled end)
    |> Enum.find(fn s -> position in s.eligible end)
    |> case do
      nil -> :error
      slot -> {:ok, slot.key}
    end
  end

  @doc "True once every slot in the template is filled."
  @spec roster_complete?([slot], [String.t()]) :: boolean()
  def roster_complete?(slots, filled), do: length(filled) >= length(slots)
end
