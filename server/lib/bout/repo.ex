defmodule Bout.Repo do
  use Ecto.Repo,
    otp_app: :bout,
    adapter: Ecto.Adapters.Postgres
end
