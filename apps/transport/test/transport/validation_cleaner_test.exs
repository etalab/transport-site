defmodule Transport.ValidationCleanerTest do
  use ExUnit.Case
  alias Ecto.Adapters.SQL.Sandbox
  alias DB.{Repo, Resource, Validation}

  def date(prior_days),
    do:
      Date.utc_today()
      |> Date.add(prior_days)
      |> Date.to_iso8601()

  setup do
    :ok = Sandbox.checkout(Repo)
    # the setup is:
    # 2 resources with validation (one 3 months ago, one 1 day ago)
    # 2 validations without resource (one 3 months ago, one 1 day ago)
    {:ok, _} =
      %Resource{
        url: "https://link.to/angers.zip",
        validation: %Validation{
          details: %{},
          date: date(-1),
          max_error: "Error",
          validation_latest_content_hash: "a_content_hash",
          data_vis: %{}
        },
        metadata: %{},
        title: "angers.zip",
        modes: ["ferry"],
        features: ["tarifs"]
      }
      |> Repo.insert()

    {:ok, _} =
      %Resource{
        url: "https://link.to/another_gtfs.zip",
        validation: %Validation{
          details: %{},
          date: date(-90),
          max_error: "Error",
          validation_latest_content_hash: "a_content_hash",
          data_vis: %{}
        },
        metadata: %{},
        title: "another_gtfs.zip",
        modes: ["bus"],
        features: []
      }
      |> Repo.insert()

    {:ok, _} =
      %Validation{
        details: %{},
        date: date(-1),
        on_the_fly_validation_metadata: %{},
        data_vis: %{}
      }
      |> Repo.insert()

    {:ok, _} =
      %Validation{
        details: %{},
        date: date(-90),
        on_the_fly_validation_metadata: %{},
        data_vis: %{}
      }
      |> Repo.insert()

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo)
      Repo.delete_all(Resource)
      Repo.delete_all(Validation)
    end)

    :ok
  end

  test "check validation cleaning" do
    assert Repo.aggregate(Validation, :count, :id) == 4

    Transport.ValidationCleaner.clean_old_validations()

    # only the validation without resource created 3 months ago should have been cleaned
    # the validation linked to resources should never be cleaned
    assert Repo.aggregate(Validation, :count, :id) == 3
  end
end
