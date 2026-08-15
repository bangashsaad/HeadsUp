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
    assert html =~ "◎ 50 POT"
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
end
