defmodule DB.ProcessingReport do
  @moduledoc """
  A generic reporting structure used to store a JSON-type report.

  Currently only used for IRVE, which means I've not added a column to
  namespace that and allow expanded use (this will be added later).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "processing_reports" do
    field(:content, :map)

    timestamps()
  end

  @doc false
  def changeset(processing_report, attrs) do
    processing_report
    |> cast(attrs, [:content])
    |> validate_required([])
  end
end
