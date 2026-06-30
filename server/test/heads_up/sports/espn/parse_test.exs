defmodule HeadsUp.Sports.Espn.ParseTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Espn.Parse

  describe "normalize_name/1" do
    test "lowercases and drops apostrophes/periods without inserting a space" do
      assert Parse.normalize_name("A'ja Wilson") == "aja wilson"
      assert Parse.normalize_name("Amon-Ra St. Brown") == "amon ra st brown"
    end

    test "strips accents to plain ascii" do
      assert Parse.normalize_name("Nikola Jokić") == "nikola jokic"
    end

    test "collapses runs of punctuation/whitespace and trims" do
      assert Parse.normalize_name("  Vladimir   Guerrero  Jr.  ") == "vladimir guerrero jr"
    end

    test "tolerates non-strings" do
      assert Parse.normalize_name(nil) == ""
    end
  end

  describe "normalize_position/1" do
    test "maps coarse and long-form positions to G/F/C" do
      assert Parse.normalize_position("G") == "G"
      assert Parse.normalize_position("Guard") == "G"
      assert Parse.normalize_position("Forward") == "F"
      assert Parse.normalize_position("Center") == "C"
    end

    test "coarsens legacy granular positions" do
      assert Parse.normalize_position("PG") == "G"
      assert Parse.normalize_position("SG") == "G"
      assert Parse.normalize_position("SF") == "F"
      assert Parse.normalize_position("PF") == "F"
      assert Parse.normalize_position("C") == "C"
    end

    test "defaults garbage/blank/nil to G" do
      assert Parse.normalize_position("") == "G"
      assert Parse.normalize_position("???") == "G"
      assert Parse.normalize_position(nil) == "G"
    end
  end

  describe "stat_value/3" do
    @labels ~w(MIN PTS FG 3PT FT REB AST TO STL BLK)
    @stats ~w(36 21 9-17 0-0 3-4 14 2 0 3 1)

    test "reads a cell by its label" do
      assert Parse.stat_value(@labels, @stats, "PTS") == "21"
      assert Parse.stat_value(@labels, @stats, "REB") == "14"
      assert Parse.stat_value(@labels, @stats, "3PT") == "0-0"
    end

    test "missing label or short row yields nil" do
      assert Parse.stat_value(@labels, @stats, "NOPE") == nil
      assert Parse.stat_value(["PTS"], [], "PTS") == nil
    end
  end

  describe "made_from/1" do
    test "extracts the made count from a made-attempted cell" do
      assert Parse.made_from("4-10") == 4
      assert Parse.made_from("0-0") == 0
    end

    test "tolerates blanks and nil" do
      assert Parse.made_from("--") == 0
      assert Parse.made_from("") == 0
      assert Parse.made_from(nil) == 0
    end
  end

  describe "to_int/1" do
    test "passes ints, truncates floats, parses strings, junk -> 0" do
      assert Parse.to_int(21) == 21
      assert Parse.to_int(21.8) == 21
      assert Parse.to_int("17") == 17
      assert Parse.to_int("  9  ") == 9
      assert Parse.to_int("DNP") == 0
      assert Parse.to_int(nil) == 0
    end
  end
end
