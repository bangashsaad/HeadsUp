defmodule HeadsUp.SocialTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Repo, Social}
  alias HeadsUp.Social.Friendship

  setup do
    %{a: user("a"), b: user("b")}
  end

  describe "public_profile/2" do
    test "a stranger shows relationship none", %{a: a, b: b} do
      assert {:ok, %{user: %{id: bid}, relationship: "none", friendship_id: nil}} = Social.public_profile(a, b.id)
      assert bid == b.id
    end

    test "tracks the request direction from the viewer's side", %{a: a, b: b} do
      {:ok, f} = Social.send_friend_request(a, b.id)

      assert {:ok, %{relationship: "request_sent", friendship_id: fid}} = Social.public_profile(a, b.id)
      assert fid == f.id
      assert {:ok, %{relationship: "request_received"}} = Social.public_profile(b, a.id)
    end

    test "accepted friendships show friends", %{a: a, b: b} do
      Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
      assert {:ok, %{relationship: "friends"}} = Social.public_profile(a, b.id)
    end

    test "your own profile is self; unknown ids are not found", %{a: a} do
      assert {:ok, %{relationship: "self"}} = Social.public_profile(a, a.id)
      assert {:error, :not_found} = Social.public_profile(a, -1)
    end
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})

    u
  end
end
