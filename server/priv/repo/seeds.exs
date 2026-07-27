# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Bout.Repo.insert!(%Bout.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Seed the sports player & game pool (idempotent — safe to re-run).
Bout.Sports.Seeds.run()
IO.puts("Seeded #{Bout.Sports.count_players()} players.")
