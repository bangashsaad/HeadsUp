defmodule HeadsUpWeb.LiveComponentsTest do
  @moduledoc """
  The live screen's scores-present path — the branch that shipped untested and
  crashed the moment a real draft finished. These render the components with
  the exact shape LiveJSON emits, so a missing assign fails here instead of in
  production.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HeadsUpWeb.LiveLive

  defp side(me?, name, total) do
    %{
      is_me: me?,
      total: total,
      user: %{id: if(me?, do: 1, else: 2), username: name},
      players: [
        %{
          name: "Test Player",
          points: total,
          line: "",
          slot: "G1",
          position: "G",
          team: "TST",
          player_id: 9,
          stat_line: %{},
          headshot_url: nil,
          game: %{state: "pre", detail: "8/15 - 7:00 PM EDT"}
        }
      ]
    }
  end

  defp duel, do: %{sport: "wnba", roster_size: 5, stake_coins: 25, opponent_id: 2, challenger_id: 1}

  test "the hero renders with real score sides — the path that crashed in prod" do
    me = side(true, "sp1ke", 0.0)
    them = side(false, "mike_hoops", 0.0)
    live = %{sides: [me, them], games: %{final: 0, live: 3, upcoming: 7}}

    html =
      render_component(&LiveLive.hero/1,
        sides: {me, them},
        duel: duel(),
        live: live,
        me_name: "sp1ke"
      )

    assert html =~ "SP1KE"
    assert html =~ "MIKE_HOOPS"
    assert html =~ "3 FIVE" == false
    assert html =~ "RIVALRY GAME"
    refute html =~ "POT"
  end

  test "the hero handles integer totals without arithmetic crashes" do
    me = side(true, "a", 12)
    them = side(false, "b", 9)
    live = %{sides: [me, them], games: %{final: 1, live: 0, upcoming: 0}}

    html = render_component(&LiveLive.hero/1, sides: {me, them}, duel: duel(), live: live, me_name: "a")
    assert html =~ "VS"
  end

  test "a roster column renders players with and without headshots" do
    html = render_component(&LiveLive.five/1, side: side(true, "sp1ke", 10.0), mine: true)
    assert html =~ "YOUR"
    assert html =~ "Test Player"
  end

  describe "game detail box rendering" do
    # The template-conversion bug class: a binding the mock had that the data
    # doesn't. Rendering the shaped box exercises every row attribute.
    test "box rows render from the shaped data without mock-only keys" do
      box = %{
        teams: [
          %{
            logo: nil,
            head: "TST BOX SCORE",
            groups: [
              %{
                label: "HITTING",
                columns: ["AB", "H"],
                rows: [%{name: "Row Player", fan: 7.5, stats: ["4", "2"]}]
              }
            ]
          }
        ]
      }

      html =
        render_component(&HeadsUpWeb.GameDetailLive.box_section/1, box: box, sport: "mlb", state: "post")

      assert html =~ "TST BOX SCORE"
      assert html =~ "Row Player"
      assert html =~ "7.5"
    end
  end
end
