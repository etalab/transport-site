defmodule Transport.Test.Transport.Jobs.DatasetQualityScoreTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory

  import Transport.Jobs.{DatasetAvailabilityScore, DatasetComplianceScore, DatasetFreshnessScore, DatasetQualityScore}

  doctest Transport.Jobs.DatasetQualityScore, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "resource last today metadata" do
    test "there is none" do
      resource = insert(:resource)

      insert(:resource_metadata,
        resource_id: resource.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-3, :day)
      )

      assert resource_last_metadata_from_today(resource.id) == nil
    end

    test "there is one" do
      resource = insert(:resource)
      # most recent metadata for today
      metadata = insert(:resource_metadata, resource_id: resource.id, inserted_at: DateTime.utc_now())

      # metadata for today, but older
      insert(:resource_metadata,
        resource_id: resource.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :minute)
      )

      assert resource_last_metadata_from_today(resource.id) == metadata
    end
  end

  describe "resource freshness computation" do
    test "up to date GTFS resource" do
      %{resource: resource = %{id: resource_id}, resource_metadata: %{id: metadata_id, inserted_at: inserted_at}} =
        insert_up_to_date_resource_and_friends()

      assert %{
               format: "GTFS",
               freshness: 1.0,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end

    test "outdated GTFS resource" do
      %{resource: resource} = insert_outdated_resource_and_friends()

      assert %{
               format: "GTFS",
               freshness: +0.0,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: _
             } = resource_freshness(resource)
    end

    test "future GTFS resource" do
      # insert a GTFS with validity dates in the future
      %{resource: resource} = insert_resource_and_friends(Date.utc_today() |> Date.add(365), [])

      assert %{
               format: "GTFS",
               freshness: nil,
               raw_measure: %{end_date: _, start_date: _},
               resource_id: _
             } = resource_freshness(resource)
    end

    test "GTFS resource without metadata" do
      resource = insert(:resource, format: "GTFS")

      assert %{format: "GTFS", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "GTFS with empty metadata" do
      resource = insert(:resource, format: "GTFS")
      resource_history = insert(:resource_history, resource_id: resource.id)

      validation =
        insert(:multi_validation,
          validator: Transport.Validators.GTFSTransport.validator_name(),
          resource_history_id: resource_history.id
        )

      insert(:resource_metadata,
        multi_validation_id: validation.id,
        metadata: %{"start_date" => nil, "end_date" => nil}
      )

      assert %{format: "GTFS", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "up to date GBFS resource" do
      resource = %{id: resource_id} = insert(:resource, format: "gbfs")

      %{id: metadata_id, inserted_at: inserted_at} =
        insert(:resource_metadata,
          resource_id: resource.id,
          metadata: %{"feed_timestamp_delay" => 10}
        )

      assert %{
               format: "gbfs",
               freshness: 1.0,
               raw_measure: 10,
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end

    test "outdated GBFS resource" do
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 1000}
      )

      assert %{format: "gbfs", freshness: +0.0, raw_measure: 1000, resource_id: _} = resource_freshness(resource)
    end

    test "GBFS resource without metadata for today" do
      resource = insert(:resource, format: "gbfs")

      insert(:resource_metadata,
        resource_id: resource.id,
        metadata: %{"feed_timestamp_delay" => 0},
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert %{format: "gbfs", freshness: nil, raw_measure: nil, resource_id: _} = resource_freshness(resource)
    end

    test "up to date GTFS-RT resource" do
      resource = %{id: resource_id} = insert(:resource, format: "gtfs-rt")

      %{id: metadata_id, inserted_at: inserted_at} =
        insert(:resource_metadata,
          resource_id: resource.id,
          metadata: %{"feed_timestamp_delay" => 10}
        )

      assert %{
               format: "gtfs-rt",
               freshness: 1.0,
               raw_measure: 10,
               resource_id: ^resource_id,
               metadata_id: ^metadata_id,
               metadata_inserted_at: ^inserted_at
             } = resource_freshness(resource)
    end

    test "for a GTFS-Flex" do
      resource = insert(:resource, format: "GTFS")

      resource_history =
        insert(:resource_history,
          resource_id: resource.id,
          payload: %{"format" => "GTFS", "filenames" => ["stops.txt", "locations.geojson"]}
        )

      assert DB.ResourceHistory.gtfs_flex?(resource_history)

      validation =
        insert(:multi_validation,
          validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
          resource_history_id: resource_history.id
        )

      insert(:resource_metadata,
        multi_validation_id: validation.id,
        metadata: metadata = %{start_date: Date.utc_today() |> Date.add(-5), end_date: Date.utc_today() |> Date.add(5)}
      )

      assert %{
               freshness: 1.0,
               raw_measure: ^metadata
             } = resource_freshness(resource)
    end
  end

  describe "resource_availability" do
    test "with no unavailabilites" do
      resource = insert(:resource)

      assert %{
               availability: 1.0,
               raw_measure: nil,
               resource_id: resource.id
             } == resource_availability(resource)
    end

    test "with an ongoing unavailability" do
      resource = insert(:resource)
      insert(:resource_unavailability, start: hours_ago(2), resource: resource)

      assert %{
               availability: +0.0,
               raw_measure: (22 / 24 * 100) |> Float.floor(1),
               resource_id: resource.id
             } == resource_availability(resource)
    end

    test "with a past availability" do
      resource = insert(:resource)
      insert(:resource_unavailability, start: hours_ago(48), end: hours_ago(23), resource: resource)

      assert %{
               availability: 0.5,
               raw_measure: (23 / 24 * 100) |> Float.floor(1),
               resource_id: resource.id
             } == resource_availability(resource)
    end
  end

  describe "current dataset availability" do
    test "2 resources with availability at 100%" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: 1.0, raw_measure: nil, resource_id: r2.id}
                 ]
               },
               score: 1.0
             } == current_dataset_availability(dataset.id)
    end

    test "excludes documentation resources to compute the score" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false, type: "documentation")

      assert DB.Resource.documentation?(r2)

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id}
                 ]
               },
               score: 1.0
             } == current_dataset_availability(dataset.id)
    end

    test "2 resources, one down for a long time" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)
      insert(:resource_unavailability, resource: r2, start: hours_ago(25))

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: +0.0, raw_measure: 0, resource_id: r2.id}
                 ]
               },
               score: 0.5
             } == current_dataset_availability(dataset.id)
    end

    test "2 resources, one down for a short period" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)
      r2 = insert(:resource, dataset: dataset, is_community_resource: false)
      insert(:resource_unavailability, resource: r2, start: hours_ago(1))

      assert %{
               details: %{
                 resources: [
                   %{availability: 1.0, raw_measure: nil, resource_id: r1.id},
                   %{availability: 0.5, raw_measure: (23 / 24 * 100) |> Float.floor(1), resource_id: r2.id}
                 ]
               },
               score: 0.75
             } == current_dataset_availability(dataset.id)
    end

    test "an hidden dataset with 0 resources" do
      dataset = insert(:dataset, is_active: true, is_hidden: true)

      assert [] == dataset |> DB.Repo.preload(:resources) |> Map.fetch!(:resources)

      assert %{score: +0.0, details: %{resources: []}} == current_dataset_availability(dataset.id)
    end
  end

  describe "current dataset freshness" do
    test "2 resources with freshness" do
      # dataset, with 1 GTFS resource
      %{dataset: dataset, resource: %{id: resource_id}} = insert_up_to_date_resource_and_friends()

      # we add a GTFS realtime resource to the dataset
      %{id: resource_id_2} = insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)

      insert(:resource_metadata,
        resource_id: resource_id_2,
        metadata: %{"feed_timestamp_delay" => 1000}
      )

      assert %{score: 0.5, details: %{resources: resources}} = current_dataset_freshness(dataset.id)

      assert [
               %{
                 format: "GTFS",
                 freshness: 1.0,
                 raw_measure: %{end_date: end_date, start_date: start_date},
                 resource_id: ^resource_id
               },
               %{
                 format: "gtfs-rt",
                 freshness: +0.0,
                 raw_measure: 1000,
                 resource_id: ^resource_id_2
               }
             ] =
               resources |> Enum.sort_by(fn %{format: format} -> format end)

      today = Date.utc_today()
      assert Date.diff(today, start_date) > 0 and Date.diff(end_date, today) > 0
    end

    test "2 resources, but only one with freshness" do
      # dataset, with 1 outdated GTFS resource
      %{dataset: dataset, resource: %{id: resource_id}} = insert_outdated_resource_and_friends()

      # we add a GTFS realtime resource to the dataset, but no metadata
      insert(:resource, format: "gtfs-rt", dataset_id: dataset.id, is_community_resource: false)

      # average freshness for only 1 resource with freshness information available
      assert %{
               score: +0.0,
               details: %{
                 resources: [
                   %{
                     format: "GTFS",
                     freshness: +0.0,
                     raw_measure: %{end_date: _, start_date: _},
                     resource_id: ^resource_id
                   },
                   %{
                     format: "gtfs-rt",
                     freshness: nil,
                     raw_measure: nil,
                     resource_id: _
                   }
                 ]
               }
             } = current_dataset_freshness(dataset.id)
    end
  end

  describe "current dataset compliance" do
    test "GTFS-RT and documentation resources are ignored, GeoJSON with schema is used" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)

      geojson_resource =
        insert(:resource, dataset: dataset, format: "geojson", schema_name: "etalab/#{Ecto.UUID.generate()}")

      rh_geojson_resource = insert(:resource_history, resource: geojson_resource)

      # A documentation resource, with a ResourceHistory but no validation is ignored
      insert(:resource_history, resource: insert(:resource, dataset: dataset, format: "pdf", type: "documentation"))

      # Should be ignored: we don't use the GTFS-RT validator
      insert(:multi_validation, %{
        validator: Transport.Validators.GTFSRT.validator_name(),
        resource: insert(:resource, dataset: dataset, format: "gtfs-rt"),
        max_error: "ERROR"
      })

      insert(:multi_validation, %{
        resource_history: rh_geojson_resource,
        validator: Transport.Validators.EXJSONSchema.validator_name(),
        result: %{"has_errors" => true},
        inserted_at: DateTime.utc_now() |> DateTime.add(-45, :minute)
      })

      assert %{
               score: 0,
               details: %{
                 resources: [
                   %{compliance: +0.0, raw_measure: %{"has_errors" => true}, resource_id: geojson_resource.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end

    test "with 2 GTFS: a Fatal and a Warning" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)

      insert(:multi_validation, %{
        resource_history:
          insert(:resource_history, resource: gtfs_1 = insert(:resource, dataset: dataset, format: "GTFS")),
        validator: Transport.Validators.GTFSTransport.validator_name(),
        max_error: "Error"
      })

      insert(:multi_validation, %{
        resource_history:
          insert(:resource_history, resource: gtfs_2 = insert(:resource, dataset: dataset, format: "GTFS")),
        validator: Transport.Validators.GTFSTransport.validator_name(),
        max_error: "Warning"
      })

      assert %{
               score: 0.5,
               details: %{
                 resources: [
                   %{compliance: +0.0, raw_measure: %{"max_error" => "Error"}, resource_id: gtfs_1.id},
                   %{compliance: 1.0, raw_measure: %{"max_error" => "Warning"}, resource_id: gtfs_2.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end

    test "with a single GTFS with a Warning" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)

      insert(:multi_validation, %{
        resource_history:
          insert(:resource_history, resource: gtfs = insert(:resource, dataset: dataset, format: "GTFS")),
        validator: Transport.Validators.GTFSTransport.validator_name(),
        max_error: "Warning"
      })

      assert %{
               score: 1.0,
               details: %{
                 resources: [
                   %{compliance: 1.0, raw_measure: %{"max_error" => "Warning"}, resource_id: gtfs.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end

    test "with a single NeTEx resource with an error" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)

      insert(:multi_validation, %{
        resource_history:
          insert(:resource_history, resource: netex = insert(:resource, dataset: dataset, format: "NeTEx")),
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        max_error: "error"
      })

      assert %{
               score: 0,
               details: %{
                 resources: [
                   %{compliance: +0.0, raw_measure: %{"max_error" => "error"}, resource_id: netex.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end

    test "handles validation_performed = false with 2 resources" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
      schema_name = "etalab/#{Ecto.UUID.generate()}"
      zip_resource = insert(:resource, dataset: dataset, format: "zip", schema_name: schema_name)
      geojson_resource = insert(:resource, dataset: dataset, format: "geojson", schema_name: schema_name)

      insert(:multi_validation, %{
        resource_history: insert(:resource_history, resource: geojson_resource),
        validator: Transport.Validators.EXJSONSchema.validator_name(),
        result: %{"has_errors" => false},
        inserted_at: DateTime.utc_now() |> DateTime.add(-45, :minute)
      })

      insert(:multi_validation, %{
        resource_history: insert(:resource_history, resource: zip_resource),
        validator: Transport.Validators.EXJSONSchema.validator_name(),
        result: %{"validation_performed" => false},
        inserted_at: DateTime.utc_now() |> DateTime.add(-45, :minute)
      })

      assert %{
               score: 1.0,
               details: %{
                 resources: [
                   %{compliance: nil, raw_measure: %{"validation_performed" => false}, resource_id: zip_resource.id},
                   %{compliance: 1.0, raw_measure: %{"has_errors" => false}, resource_id: geojson_resource.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end

    test "handles validation result = nil, uses the digest" do
      dataset = insert(:dataset)
      geojson_resource = insert(:resource, dataset: dataset, format: "geojson")

      insert(:multi_validation, %{
        resource_history: insert(:resource_history, resource: geojson_resource),
        validator: Transport.Validators.EXJSONSchema.validator_name(),
        result: nil,
        digest: %{"errors_count" => 0}
      })

      assert %{
               score: 1.0,
               details: %{
                 resources: [
                   %{compliance: 1.0, raw_measure: %{"errors_count" => 0}, resource_id: geojson_resource.id}
                 ]
               }
             } == current_dataset_compliance(dataset.id)
    end
  end

  describe "last_dataset_score" do
    test "fetches the latest non-nil score for yesterday" do
      dataset = insert(:dataset, is_active: true)
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day)
      yesterday_after = yesterday |> DateTime.add(5, :second)

      insert(:dataset_score, dataset: dataset, topic: :availability, score: 0.5, timestamp: yesterday)
      insert(:dataset_score, dataset: dataset, topic: :availability, score: 0.75, timestamp: yesterday_after)
      insert(:dataset_score, dataset: dataset, topic: :freshness, score: 1.0, timestamp: yesterday)
      insert(:dataset_score, dataset: dataset, topic: :freshness, score: nil, timestamp: yesterday_after)
      insert(:dataset_score, dataset: dataset, topic: :compliance, score: 0.8, timestamp: yesterday)
      insert(:dataset_score, dataset: dataset, topic: :compliance, score: nil, timestamp: yesterday_after)

      assert %DB.DatasetScore{score: 0.75, topic: :availability} = last_dataset_score(dataset.id, :availability)
      assert %DB.DatasetScore{score: 1.0, topic: :freshness} = last_dataset_score(dataset.id, :freshness)
      assert %DB.DatasetScore{score: 0.8, topic: :compliance} = last_dataset_score(dataset.id, :compliance)
    end

    test "does not use scores if they are more than 7-day old" do
      dataset = insert(:dataset, is_active: true)
      topics = Ecto.Enum.values(DB.DatasetScore, :topic)

      insert(:dataset_score,
        dataset: dataset,
        topic: Enum.random(topics),
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-8, :day)
      )

      Enum.each(topics, fn topic ->
        assert is_nil(last_dataset_score(dataset.id, topic))
      end)
    end
  end

  describe "save_dataset_score for availability" do
    test "computes availability from yesterday and today" do
      dataset = insert(:dataset, is_active: true)
      r1 = insert(:resource, dataset: dataset, is_community_resource: false)

      # we save an availability score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # a score for another topic
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      # expected score is 0.5 * 0.9 + 1. * (1. - 0.9) = 0.55
      # see exp_smoothing/3 function
      assert {
               :ok,
               %DB.DatasetScore{id: _id, topic: :availability, score: 0.55, timestamp: timestamp, details: details}
             } = save_dataset_score(dataset.id, :availability)

      assert DateTime.diff(timestamp, DateTime.utc_now(), :second) < 3
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3

      assert %{
               previous_score: 0.5,
               today_score: 1.0,
               resources: [
                 %{
                   availability: 1.0,
                   resource_id: r1.id,
                   raw_measure: nil
                 }
               ]
             } == details
    end
  end

  describe "save_dataset_score for compliance" do
    test "computes compliance from yesterday and today" do
      dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)

      insert(:multi_validation, %{
        resource_history:
          insert(:resource_history,
            resource: %DB.Resource{id: gtfs_id} = insert(:resource, dataset: dataset, format: "GTFS")
          ),
        validator: Transport.Validators.GTFSTransport.validator_name(),
        max_error: "Warning"
      })

      # we save a compliance score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :compliance,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # a score for another topic
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      # expected score is 0.5 * 0.95 + 1. * (1. - 0.95) = 0.525
      # see exp_smoothing/3 function
      assert {
               :ok,
               %DB.DatasetScore{
                 id: _id,
                 topic: :compliance,
                 score: 0.525,
                 timestamp: timestamp,
                 details: %{
                   previous_score: 0.5,
                   today_score: 1.0,
                   resources: [%{compliance: 1.0, raw_measure: %{"max_error" => "Warning"}, resource_id: ^gtfs_id}]
                 }
               }
             } = save_dataset_score(dataset.id, :compliance)

      assert DateTime.diff(timestamp, DateTime.utc_now(), :second) < 3
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3
    end
  end

  describe "save_dataset_score for freshness" do
    test "compute freshness from yesterday and today" do
      %{dataset: dataset, resource: %{id: resource_id}, resource_metadata: %{id: metadata_id}} =
        insert_up_to_date_resource_and_friends()

      # we save a freshness score for yesterday
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # another irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      # expected score is 0.5 * 0.9 + 1. * (1. - 0.9)
      # see exp_smoothing/3 function
      assert %{id: _id, topic: :freshness, score: 0.55, timestamp: timestamp, details: details} = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3

      assert %{
               previous_score: 0.5,
               today_score: 1.0,
               resources: [
                 %{
                   format: "GTFS",
                   freshness: 1.0,
                   resource_id: ^resource_id,
                   raw_measure: %{start_date: start_date, end_date: end_date},
                   metadata_id: ^metadata_id
                 }
               ]
             } = details

      assert Date.diff(Date.utc_today(), start_date) > 0 and Date.diff(end_date, Date.utc_today()) > 0
    end

    test "no score yesterday" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()

      # an irrelevant score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :availability,
        score: 1.0,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      # expected score is todays's score (no existing history)
      assert %{
               id: _id,
               topic: :freshness,
               score: 1.0,
               timestamp: timestamp,
               details: %{previous_score: nil, today_score: 1.0}
             } = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2
    end

    test "no score at all" do
      dataset = insert(:dataset)
      assert DB.DatasetScore |> DB.Repo.all() |> length() == 0

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      # expected score is nil
      assert %{
               id: _id,
               topic: :freshness,
               score: nil,
               timestamp: timestamp,
               details: %{today_score: nil, previous_score: nil}
             } = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1
    end

    test "new score is computed with last non nil score" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # last score is nil
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: nil,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # but existing score before
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-2, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      # score is computed with today's freshness and last non nil score.
      assert %{
               id: _id,
               topic: :freshness,
               score: 0.55,
               timestamp: timestamp,
               details: %{today_score: 1.0, previous_score: 0.5}
             } = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 3
    end

    test "new score is computed with last non nil score, unless it is too old" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      # old existing score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-8, :day)
      )

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 1

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      # score is computed from scratch, previous score is not used
      assert %{
               id: _id,
               topic: :freshness,
               score: 1.0,
               timestamp: timestamp,
               details: %{today_score: 1.0, previous_score: nil}
             } = score

      assert DateTime.diff(timestamp, DateTime.utc_now()) < 3

      assert DB.DatasetScore |> DB.Repo.all() |> length() == 2
    end

    test "last score timestamp is not today" do
      # if a score is for some reason computed many times in one day
      # we don't want to massively change the score
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()

      # yesterday's score
      insert(:dataset_score,
        dataset_id: dataset.id,
        topic: :freshness,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      {:ok, score} = save_dataset_score(dataset.id, :freshness)
      # score is computed with yesterday's score
      assert %{
               id: id1,
               topic: :freshness,
               score: 0.55,
               timestamp: _timestamp,
               details: %{today_score: 1.0, previous_score: 0.5}
             } = score

      # we force refresh the score computation
      # it should use yesterday's score again
      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      assert %{
               id: id2,
               topic: :freshness,
               score: 0.55,
               timestamp: _timestamp,
               details: %{today_score: 1.0, previous_score: 0.5}
             } = score

      assert id2 > id1
    end

    test "dataset without scorable resource" do
      dataset = insert(:dataset, is_active: true)
      %{id: resource_id} = insert(:resource, dataset_id: dataset.id, format: "csv", is_community_resource: false)

      {:ok, score} = save_dataset_score(dataset.id, :freshness)

      assert %{
               topic: :freshness,
               score: nil,
               details: %{
                 previous_score: nil,
                 today_score: nil,
                 resources: [%{resource_id: ^resource_id, format: "csv", freshness: nil}]
               }
             } = score
    end

    test "last score is not nil and current's score is nil" do
      %DB.Dataset{id: dataset_id} = insert(:dataset, is_active: true)
      topic = :freshness

      insert(:dataset_score,
        dataset_id: dataset_id,
        topic: topic,
        score: 0.5,
        timestamp: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      assert %DB.DatasetScore{dataset_id: ^dataset_id, score: 0.5, topic: ^topic} =
               last_dataset_score(dataset_id, topic)

      assert %{details: %{resources: []}, score: nil} == current_dataset_freshness(dataset_id)

      assert {:ok,
              %DB.DatasetScore{
                dataset_id: ^dataset_id,
                score: nil,
                topic: ^topic,
                details: %{previous_score: 0.5, today_score: nil, resources: []}
              }} = save_dataset_score(dataset_id, topic)
    end
  end

  test "resource_ids_with_unavailabilities" do
    r1 = insert(:resource)
    r2 = insert(:resource)
    r3 = insert(:resource)
    insert(:resource_unavailability, resource: r1, start: hours_ago(5))
    insert(:resource_unavailability, resource: r2, start: hours_ago(48), end: hours_ago(30))
    insert(:resource_unavailability, resource: r3, start: hours_ago(5), end: hours_ago(2))
    insert(:resource_unavailability, resource: r3, start: hours_ago(30), end: hours_ago(10))

    assert [r1.id, r3.id] |> Enum.sort() == resource_ids_with_unavailabilities() |> Enum.sort()
  end

  describe "DatasetQualityScore" do
    test "job saves multiple topics for a dataset" do
      assert DB.DatasetScore |> DB.Repo.all() |> Enum.empty?()

      %{dataset: %DB.Dataset{id: dataset_id} = dataset, resource: %DB.Resource{id: resource_id}} =
        insert_up_to_date_resource_and_friends()

      assert :ok == perform_job(Transport.Jobs.DatasetQualityScore, %{"dataset_id" => dataset.id})

      assert [
               %DB.DatasetScore{
                 dataset_id: ^dataset_id,
                 topic: :freshness,
                 score: 1.0,
                 details: %{
                   "previous_score" => nil,
                   "today_score" => 1.0,
                   "resources" => [
                     %{
                       "format" => "GTFS",
                       "freshness" => 1.0,
                       "raw_measure" => %{"end_date" => _, "start_date" => _},
                       "resource_id" => ^resource_id
                     }
                   ]
                 }
               },
               %DB.DatasetScore{
                 dataset_id: ^dataset_id,
                 topic: :availability,
                 score: 1.0,
                 details: %{
                   "previous_score" => nil,
                   "today_score" => 1.0,
                   "resources" => [%{"availability" => 1.0, "raw_measure" => nil, "resource_id" => ^resource_id}]
                 }
               },
               %DB.DatasetScore{
                 dataset_id: ^dataset_id,
                 topic: :compliance,
                 score: 1.0,
                 details: %{
                   "previous_score" => nil,
                   "today_score" => 1.0,
                   "resources" => [
                     %{"compliance" => 1.0, "raw_measure" => %{"max_error" => nil}, "resource_id" => ^resource_id}
                   ]
                 }
               }
             ] = DB.DatasetScore |> DB.Repo.all()
    end
  end

  describe "DatasetQualityScoreDispatcher" do
    test "jobs are enqueued" do
      active_dataset = insert(:dataset, is_active: true, is_hidden: false)
      hidden_dataset = insert(:dataset, is_active: true, is_hidden: true)
      inactive_dataset = insert(:dataset, is_active: false)

      assert :ok == perform_job(Transport.Jobs.DatasetQualityScoreDispatcher, %{})

      assert_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => active_dataset.id}
      )

      assert_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => hidden_dataset.id}
      )

      refute_enqueued(
        worker: Transport.Jobs.DatasetQualityScore,
        args: %{"dataset_id" => inactive_dataset.id}
      )
    end
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours, :hour) |> DateTime.truncate(:second)
  end
end
