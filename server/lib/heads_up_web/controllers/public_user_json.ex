defmodule HeadsUpWeb.PublicUserJSON do
  @moduledoc """
  The PUBLIC shape of a user — only id + username, never email or anything
  private. Use this any time we show one user to another (search, friends).
  """

  @doc """
  Search results: users plus this viewer's relationship to each, and a one-line
  blurb (record + most-played league) for the strangers list.
  """
  def search(%{results: results}) do
    %{
      users:
        Enum.map(results, fn %{user: user, relationship: rel, friendship_id: fid} ->
          public(user)
          |> Map.put(:relationship, rel)
          |> Map.put(:friendship_id, fid)
          |> Map.put(:meta, HeadsUp.Stats.blurb(user.id))
        end)
    }
  end

  def public(user) do
    %{id: user.id, username: user.username, online: HeadsUp.Accounts.online?(user)}
  end

  @doc """
  A tappable profile: who they are, your relationship to them (with the
  friendship id for accept flows), their overall record, and your
  head-to-head vs them (nil if you've never played).
  """
  def profile(%{profile: profile, record: record, vs_you: vs_you} = assigns) do
    %{
      profile: %{
        user: public(profile.user),
        relationship: profile.relationship,
        friendship_id: profile.friendship_id,
        record: record_slice(record),
        vs_you: vs_you && record_slice(vs_you),
        # The individual duels behind that head-to-head record.
        history:
          Enum.map(assigns[:history] || [], fn h ->
            %{outcome: h.outcome, points_for: h.pf, points_against: h.pa, settled_at: h.settled_at}
          end)
      }
    }
  end

  defp record_slice(r) do
    %{wins: r.wins, losses: r.losses, ties: r.ties, played: r.played, streak: r.streak}
  end
end
