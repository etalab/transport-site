defmodule DB.ResourceTest do
  use TransportWeb.ConnCase, async: true
  alias DB.Resource
  import Mox
  import DB.Factory

  doctest Resource, import: true

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  def http_validation_response do
    %HTTPoison.Response{
      status_code: 200,
      body:
        "{\"metadata\":{\"start_date\":\"2021-07-08\",\"end_date\":\"2021-10-24\",\"stop_areas_count\":588,\"stop_points_count\":1016,\"lines_count\":126,\"networks\":[\"Sté de Transport de l'Agglomération Nazairienne\"],\"modes\":[\"bus\"],\"issues_count\":{\"ExcessiveSpeed\":2,\"NullDuration\":10,\"DuplicateStops\":43},\"has_fares\":false,\"has_shapes\":true,\"some_stops_need_phone_agency\":false,\"some_stops_need_phone_driver\":false},\"validations\":{\"ExcessiveSpeed\":[{\"severity\":\"Information\",\"issue_type\":\"ExcessiveSpeed\",\"object_id\":\"22226\",\"object_type\":\"Stop\",\"object_name\":\"FossedeRotz\",\"related_objects\":[{\"id\":\"21994\",\"object_type\":\"Stop\",\"name\":\"FosseBlanc\"},{\"id\":\"118\",\"object_type\":\"Route\",\"name\":\"301\"}],\"details\":\"computed speed between the stops is 525.76 km/h (17525 m travelled in 120 seconds)\"}]}}"
    }
  end

  test "get resource related geojson infos" do
    now = DateTime.now!("Etc/UTC")

    # we insert 3 resource history for a resource
    %{id: resource_id_1} = insert(:resource)
    insert_resource_history(resource_id_1, uuid1 = Ecto.UUID.generate(), now, -3600)
    insert_resource_history(resource_id_1, uuid2 = Ecto.UUID.generate(), now)
    insert_resource_history(resource_id_1, uuid3 = Ecto.UUID.generate(), now, -3601)

    # and one for another resource
    %{id: resource_id_2} = insert(:resource)
    insert_resource_history(resource_id_2, uuid4 = Ecto.UUID.generate(), now)

    # we insert 1 conversion for each resource history
    insert_geojson_data_conversion(uuid1, "url1", 10)
    insert_geojson_data_conversion(uuid2, "url2", 12)
    # Should be ignored, this is not the default converter
    insert_geojson_data_conversion(uuid2, "url2", 14, "other_converter")
    insert_geojson_data_conversion(uuid3, "url3", 10)

    data_conversion_pending =
      insert_geojson_data_conversion(uuid4, "url4", 10, DB.DataConversion.converter_to_use("GeoJSON"), :pending)

    assert %{url: "url2", filesize: 12, resource_history_last_up_to_date_at: _} =
             Resource.get_related_geojson_info(resource_id_1)

    assert nil == Resource.get_related_geojson_info(resource_id_1 - 10)

    assert %{GeoJSON: %{url: "url2", filesize: 12, resource_history_last_up_to_date_at: _}} =
             Resource.get_related_files(%Resource{id: resource_id_1})

    # Make sure that the conversion is found only when `status=success`
    assert %{GeoJSON: nil} == Resource.get_related_files(%Resource{id: resource_id_2})
    data_conversion_pending |> Ecto.Changeset.change(%{status: :success}) |> DB.Repo.update!()

    assert %{GeoJSON: %{url: "url4", filesize: 10, resource_history_last_up_to_date_at: _}} =
             Resource.get_related_files(%Resource{id: resource_id_2})
  end

  defp insert_resource_history(resource_id, uuid, datetime, time_delta_seconds \\ 0) do
    insert(:resource_history, %{
      resource_id: resource_id,
      payload: %{uuid: uuid},
      inserted_at: DateTime.add(datetime, time_delta_seconds, :second)
    })
  end

  defp insert_geojson_data_conversion(uuid, permanent_url, filesize, converter \\ nil, status \\ :success) do
    insert(:data_conversion, %{
      resource_history_uuid: uuid,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      converter: converter || DB.DataConversion.converter_to_use("GeoJSON"),
      status: status,
      payload: %{permanent_url: permanent_url, filesize: filesize}
    })
  end

  describe "resource last content update time" do
    test "basic case" do
      %{id: resource_id} = insert(:resource)

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert expected_last_update_time == resource_id |> Resource.content_updated_at()
    end

    test "only one resource history, we don't know the resource last content update time" do
      %{id: resource_id} = insert(:resource, %{datagouv_id: datagouv_id = "datagouv_id"})

      insert(:resource_history, %{
        datagouv_id: datagouv_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      assert Resource.content_updated_at(resource_id) == nil
    end

    test "last content update time, download_datime not in payload" do
      %{id: resource_id} = insert(:resource, %{datagouv_id: datagouv_id = "datagouv_id"})
      insert(:resource_history, %{datagouv_id: datagouv_id, payload: %{}})

      assert Resource.content_updated_at(resource_id) == nil
    end

    test "last content update time, some download_datetime not in payload" do
      %{id: resource_id} = insert(:resource)
      insert(:resource_history, %{payload: %{}})

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert expected_last_update_time == resource_id |> Resource.content_updated_at()
    end
  end

  test "download url" do
    # Files hosted on data.gouv.fr
    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "file",
             url: "https://demo-static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://demo.data.gouv.fr/fake_stable_url"
           }) == latest_url

    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "file",
             url: "https://static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # Bison Futé folder
    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "remote",
             url: "http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # URLs on major object storage providers
    [
      "https://thapaasblobsuat.blob.core.windows.net/datagouv/gtfs_static.zip",
      "https://download.mywebsite.com.s3.fr-par.scw.cloud/gtfs_static.zip",
      "https://download.mywebsite.com.s3.us-east-1.amazonaws.com/gtfs_static.zip",
      "https://transport-data-gouv-fr-resource-history-prod.cellar-c2.services.clever-cloud.com/gtfs_static.zip",
      "https://s3.gra.cloud.ovh.net/gtfs_static.zip"
    ]
    |> Enum.each(fn url ->
      assert Resource.download_url(%Resource{
               dataset: %DB.Dataset{},
               filetype: "remote",
               url: url,
               latest_url: latest_url = "https://data.gouv.fr/#{Ecto.UUID.generate()}"
             }) == latest_url
    end)

    # Bison Futé files
    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "remote",
             id: id = 1,
             url: "http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/refDir.csv",
             latest_url: "https://data.gouv.fr/fake_stable_url"
           }) == resource_url(TransportWeb.Endpoint, :download, id)

    # File not hosted on data.gouv.fr
    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "file",
             url: url = "https://data.example.com/voies.geojson"
           }) ==
             url

    # Remote filetype / can direct download
    assert Resource.download_url(%Resource{
             dataset: %DB.Dataset{},
             filetype: "remote",
             url: url = "https://data.example.com/data"
           }) == url

    # http URL
    assert Resource.download_url(%Resource{
             id: id = 1,
             dataset: %DB.Dataset{},
             filetype: "remote",
             url: "http://data.example.com/data"
           }) ==
             resource_url(TransportWeb.Endpoint, :download, id)

    # file hosted on GitHub
    assert Resource.download_url(%Resource{
             id: id = 1,
             dataset: %DB.Dataset{},
             filetype: "remote",
             url:
               "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/898dc67fb19fae2464c24a85a0557e8ccce18791/bnlc-.csv"
           }) == resource_url(TransportWeb.Endpoint, :download, id)
  end

  test "invalid resource" do
    resource = %Resource{format: "GTFS", schema_name: "anything", datagouv_id: datagouv_id = Ecto.UUID.generate()}
    assert %Ecto.Changeset{valid?: false} = changeset = Resource.changeset(resource, %{})

    assert {"Public transport formats can’t have a schema set",
            [{:resource_id, nil}, {:resource_datagouv_id, datagouv_id}]} ==
             changeset.errors[:schema_name]
  end
end
