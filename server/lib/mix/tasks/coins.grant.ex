defmodule Mix.Tasks.Coins.Grant do
  @moduledoc """
  Dev tooling: mint coins into a user's wallet.

      mix coins.grant nyel@example.com 500
  """
  @shortdoc "Mint coins into a user's wallet (dev tooling)"

  use Mix.Task

  @impl Mix.Task
  def run([email, amount]) do
    Mix.Task.run("app.start")

    user = HeadsUp.Repo.get_by!(HeadsUp.Accounts.User, email: email)
    {:ok, _} = HeadsUp.Coins.grant(user.id, String.to_integer(amount), nil, %{"reason" => "dev_grant"})

    Mix.shell().info("#{user.username} now holds #{HeadsUp.Coins.balance(user.id)} coins.")
  end

  def run(_args), do: Mix.raise("usage: mix coins.grant <email> <amount>")
end
