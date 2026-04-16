defmodule ScrumPoker.Repo do
  use Ecto.Repo,
    otp_app: :scrum_poker,
    adapter: Ecto.Adapters.Postgres
end
