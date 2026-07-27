defmodule Mix.Tasks.Coins.Backfill do
  @moduledoc """
  Grants the signup coin bonus to every existing user. Idempotent — each grant
  carries the same "grant:signup:{id}" key a fresh registration would, so
  rerunning (or racing a real signup) can never double-grant.

      mix coins.backfill
  """
  @shortdoc "Grant the signup coin bonus to every existing user (idempotent)"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    users = HeadsUp.Repo.all(HeadsUp.Accounts.User)

    for user <- users do
      {:ok, _} = HeadsUp.Coins.grant_signup(user.id)
    end

    Mix.shell().info("Backfilled signup grants for #{length(users)} users.")
  end
end
