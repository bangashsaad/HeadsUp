defmodule HeadsUpWeb.PublicUserJSON do
  @moduledoc """
  The PUBLIC shape of a user — only id + username, never email or anything
  private. Use this any time we show one user to another (search, friends).
  """

  @doc "Search results: users plus this viewer's relationship to each."
  def search(%{results: results}) do
    %{
      users:
        Enum.map(results, fn %{user: user, relationship: rel, friendship_id: fid} ->
          public(user)
          |> Map.put(:relationship, rel)
          |> Map.put(:friendship_id, fid)
        end)
    }
  end

  def public(user) do
    %{id: user.id, username: user.username}
  end

  @doc """
  A tappable profile: who they are, your relationship to them (with the
  friendship id for accept flows), their overall record, and your
  head-to-head vs them (nil if you've never played).
  """
  def profile(%{profile: profile, record: record, vs_you: vs_you}) do
    %{
      profile: %{
        user: public(profile.user),
        relationship: profile.relationship,
        friendship_id: profile.friendship_id,
        record: record_slice(record),
        vs_you: vs_you && record_slice(vs_you)
      }
    }
  end

  defp record_slice(r) do
    %{wins: r.wins, losses: r.losses, ties: r.ties, played: r.played, streak: r.streak}
  end
end
