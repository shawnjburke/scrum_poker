defmodule ScrumPoker.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :string
      add :avatar_url, :string
      add :provider, :string
      add :provider_uid, :string
    end

    create unique_index(:users, [:provider, :provider_uid],
             where: "provider IS NOT NULL AND provider_uid IS NOT NULL"
           )
  end
end
