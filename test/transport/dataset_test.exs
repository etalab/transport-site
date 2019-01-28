defmodule Transport.DatasetTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias Transport.Dataset

  doctest Dataset

  @valid_changeset %{
        datagouv_id: "5bc493d08b4c416c84a69500",
        slug: "offre-de-transport-du-reseau-de-laval-agglomeration-gtfs",
        resources: [%{validation: %{}}],
        aom_id: 1
  }

  test "Region can be blank" do
    changeset = Dataset.changeset(%Dataset{}, @valid_changeset)
    assert changeset.valid?
  end

end
