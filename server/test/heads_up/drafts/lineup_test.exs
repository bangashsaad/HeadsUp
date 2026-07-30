defmodule HeadsUp.Drafts.LineupTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Drafts.Lineup

  describe "templates/0 and templates_for/1" do
    test "exposes the canonical 5/7 shapes plus the legacy presets" do
      assert Enum.sort(Lineup.templates()) == [
               "mlb_5",
               "mlb_7",
               "mlb_quick",
               "mlb_standard",
               "nba_5",
               "nba_7",
               "nba_quick",
               "nba_standard",
               "nfl_5",
               "nfl_7",
               "nfl_quick",
               "nfl_standard",
               "wnba_5",
               "wnba_7",
               "wnba_quick",
               "wnba_standard"
             ]
    end

    test "filters by sport" do
      assert Lineup.templates_for("wnba") == ["wnba_5", "wnba_7", "wnba_quick", "wnba_standard"]
      assert Lineup.templates_for("nfl") == ["nfl_5", "nfl_7", "nfl_quick", "nfl_standard"]
      assert Lineup.templates_for("xxx") == []
    end

    test "canonical shapes: sizes 5 and 7, each ending in one FLEX" do
      for sport <- ~w(wnba nba mlb nfl), size <- [5, 7] do
        slots = Lineup.slots("#{sport}_#{size}")
        assert length(slots) == size
        assert List.last(slots).label == "FLEX"
        assert Enum.count(slots, &(&1.label == "FLEX")) == 1
      end

      assert Enum.map(Lineup.slots("wnba_5"), & &1.label) == ~w(GUARD GUARD FORWARD FORWARD FLEX)
      assert Enum.map(Lineup.slots("mlb_7"), & &1.label) ==
               ~w(PITCHER PITCHER INFIELD INFIELD OUTFIELD OUTFIELD FLEX)

      assert Enum.map(Lineup.slots("nfl_5"), & &1.label) == ~w(QB RB WR WR FLEX)
      assert Enum.map(Lineup.slots("nfl_7"), & &1.label) == ~w(QB RB RB WR WR TE FLEX)
    end

    test "default_template/1 prefers the 5-slot shape for every live sport" do
      assert Lineup.default_template("wnba") == "wnba_5"
      assert Lineup.default_template("mlb") == "mlb_5"
      assert Lineup.default_template("nfl") == "nfl_5"
      assert Lineup.sizes_for("wnba") == [5, 7]
      assert Lineup.sizes_for("nfl") == [5, 7]
      # A sport with no canonical shape still falls back to its legacy preset.
      assert Lineup.default_template("xxx") == "xxx_standard"
    end

    test "the NFL FLEX takes any skill position but never a quarterback" do
      slots = Lineup.slots("nfl_5")

      assert Lineup.can_fill?(slots, ~w(QB1 RB1 WR1 WR2), "TE") == {:ok, "FLEX1"}
      assert Lineup.can_fill?(slots, ~w(QB1 RB1 WR1 WR2), "RB") == {:ok, "FLEX1"}
      assert Lineup.can_fill?(slots, ~w(QB1 RB1 WR1 WR2), "QB") == :error
    end

    test "wnba uses the coarse G/F/C scheme (the ESPN feed only emits G/F/C)" do
      assert Enum.map(Lineup.slots("wnba_quick"), & &1.label) == ~w(G F C)

      assert Enum.map(Lineup.slots("wnba_standard"), & &1.key) ==
               ~w(G1 G2 F1 F2 C1 UTIL1)

      # every WNBA slot's eligibility accepts the coarse codes the feed emits...
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), [], "G") == {:ok, "G1"}
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), [], "F") == {:ok, "F1"}
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), [], "C") == {:ok, "C1"}
      # with the C slot filled, a second center still fits UTIL (no deadlock)
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), ["C1"], "C") == {:ok, "UTIL1"}
      # ...and still accepts legacy granular codes from un-reseeded rows.
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), [], "PG") == {:ok, "G1"}
      assert Lineup.can_fill?(Lineup.slots("wnba_standard"), [], "SF") == {:ok, "F1"}
    end

    test "wnba_standard fills for a center-heavy and a one-center side (no deadlock)" do
      slots = Lineup.slots("wnba_standard")

      # C1 requires one true center per side; UTIL stays flexible — it absorbs a
      # SECOND center on one side and a guard on the other. Neither stalls.
      fill = fn positions ->
        Enum.reduce(positions, {[], true}, fn pos, {filled, ok?} ->
          case Lineup.can_fill?(slots, filled, pos) do
            {:ok, key} -> {[key | filled], ok?}
            :error -> {filled, false}
          end
        end)
      end

      {teamA, okA} = fill.(~w(G G F F C C))
      {teamB, okB} = fill.(~w(G G F F C G))
      assert okA and okB
      assert Lineup.roster_complete?(slots, teamA)
      assert Lineup.roster_complete?(slots, teamB)
    end
  end

  describe "slot_count/1" do
    test "matches each preset's slot list length" do
      assert Lineup.slot_count("nfl_quick") == 4
      assert Lineup.slot_count("nfl_standard") == 7
      assert Lineup.slot_count("nba_quick") == 3
      assert Lineup.slot_count("nba_standard") == 5
      assert Lineup.slot_count("mlb_quick") == 5
      assert Lineup.slot_count("mlb_standard") == 7
    end

    test "unknown template -> 0 (callers guard via validate_inclusion)" do
      assert Lineup.slot_count("nope") == 0
      assert Lineup.slots("nope") == []
      refute Lineup.valid?("nope")
    end
  end

  describe "can_fill?/3" do
    test "fills the first open eligible slot in template order" do
      slots = Lineup.slots("nfl_standard")
      assert Lineup.can_fill?(slots, [], "RB") == {:ok, "RB1"}
      assert Lineup.can_fill?(slots, ["RB1"], "RB") == {:ok, "RB2"}
      # both RB slots taken -> an RB falls to FLEX
      assert Lineup.can_fill?(slots, ["RB1", "RB2"], "RB") == {:ok, "FLEX1"}
    end

    test "returns :error when no open slot is eligible" do
      slots = Lineup.slots("nfl_standard")
      # all RB-capable slots (RB1, RB2, FLEX1) filled
      assert Lineup.can_fill?(slots, ["RB1", "RB2", "FLEX1"], "RB") == :error
      # a kicker has no slot in any preset -> always :error (Ks are undraftable)
      assert Lineup.can_fill?(Lineup.slots("nfl_quick"), [], "K") == :error
    end

    test "NBA G/F flex slots accept either eligible position" do
      slots = Lineup.slots("nba_quick")
      assert Lineup.can_fill?(slots, [], "PG") == {:ok, "G1"}
      assert Lineup.can_fill?(slots, [], "SG") == {:ok, "G1"}
      assert Lineup.can_fill?(slots, [], "SF") == {:ok, "F1"}
      assert Lineup.can_fill?(slots, [], "PF") == {:ok, "F1"}
      assert Lineup.can_fill?(slots, [], "C") == {:ok, "C1"}
    end

    test "MLB CI/MI/UTIL groupings" do
      slots = Lineup.slots("mlb_standard")
      assert Lineup.can_fill?(slots, [], "1B") == {:ok, "CI1"}
      assert Lineup.can_fill?(slots, [], "SS") == {:ok, "MI1"}
      # a DH only fits UTIL (no dedicated slot)
      assert Lineup.can_fill?(slots, [], "DH") == {:ok, "UTIL1"}
      # a pitcher can never fill UTIL (hitters only)
      assert Lineup.can_fill?(slots, ["SP1"], "SP") == :error
    end
  end

  describe "roster_complete?/2" do
    test "true only when every slot is filled" do
      slots = Lineup.slots("nba_quick")
      refute Lineup.roster_complete?(slots, ["G1"])
      assert Lineup.roster_complete?(slots, ["G1", "F1", "C1"])
    end
  end

  describe "shared-pool feasibility" do
    # Two teams draft from ONE board. A single-position slot of position P
    # demands 2 of P across both rosters; that must not exceed the seeded pool.
    # Pool counts reflect seeds.ex (MLB RP/C bumped to 4 each for margin).
    @pools %{
      "nfl" => %{"QB" => 8, "RB" => 8, "WR" => 8, "TE" => 4, "K" => 2},
      "nba" => %{"PG" => 8, "SG" => 4, "SF" => 4, "PF" => 4, "C" => 4},
      "wnba" => %{"PG" => 8, "SG" => 4, "SF" => 4, "PF" => 4, "C" => 4},
      "mlb" => %{
        "SP" => 5,
        "RP" => 4,
        "C" => 4,
        "1B" => 3,
        "2B" => 2,
        "3B" => 3,
        "SS" => 3,
        "OF" => 5,
        "DH" => 2
      }
    }

    test "every preset's single-position demand fits two teams in the seeded pool" do
      for template <- Lineup.templates() do
        [sport, _preset] = String.split(template, "_", parts: 2)
        pool = @pools[sport]

        demand =
          template
          |> Lineup.slots()
          |> Enum.filter(&(length(&1.eligible) == 1))
          |> Enum.frequencies_by(&hd(&1.eligible))

        for {pos, n} <- demand do
          assert 2 * n <= pool[pos],
                 "#{template}: needs #{2 * n} #{pos}, pool has #{pool[pos]}"
        end
      end
    end
  end
end
