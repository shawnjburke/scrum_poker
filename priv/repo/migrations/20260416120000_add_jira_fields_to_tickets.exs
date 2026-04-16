defmodule ScrumPoker.Repo.Migrations.AddJiraFieldsToTickets do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :issue_type, :string
      add :issue_id, :string
      add :parent_id, :string
      add :priority, :string
    end
  end
end
