defmodule Transport.ProcessingReport do
  use Ecto.Schema
  import Ecto.Changeset

  schema "processing_reports" do
    field :content, :map

    timestamps()
  end

  @doc false
  def changeset(processing_report, attrs) do
    processing_report
    |> cast(attrs, [:content])
    |> validate_required([])
  end
end
