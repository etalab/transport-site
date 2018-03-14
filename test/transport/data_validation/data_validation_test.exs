defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation

  doctest DataValidation

  test "finds a project" do
    use_cassette "data_validation/find_project-ok" do
      assert {:ok, %{name: "transport", id: id}} = DataValidation.find_project(%{name: "transport"})
      refute is_nil(id)
    end
  end

  test "creates a project" do
    use_cassette "data_validation/create_project-ok" do
      assert {:ok, %{name: "transport", id: id}} = DataValidation.create_project(%{name: "transport"})
      refute is_nil(id)
    end
  end

  test "finds a feed source" do
    {:ok, project} = use_cassette "data_validation/find_project-ok" do
      DataValidation.find_project(%{name: "transport"})
    end

    use_cassette "data_validation/find_feed_source-ok" do
      assert {:ok, %{name: "tisseo", url: url, id: id}} = DataValidation.find_feed_source(%{project: project, name: "tisseo"})
      refute is_nil(url)
      refute is_nil(id)
    end
  end

  test "creates a feed source" do
    {:ok, project} = use_cassette "data_validation/find_project-ok" do
      DataValidation.find_project(%{name: "transport"})
    end

    use_cassette "data_validation/create_feed_source-ok" do
      name = "tisseo"
      url  = "https://data.toulouse-metropole.fr/api/v2/catalog/datasets/tisseo-gtfs/files/bd1298f158bc39ed9065e0c17ebb773b"
      assert {:ok, %{name: ^name, url: ^url, id: id}} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
      refute is_nil(id)
    end
  end

  test "validates a feed source" do
    {:ok, project} = use_cassette "data_validation/find_project-ok" do
      DataValidation.find_project(%{name: "transport"})
    end

    {:ok, feed_source} = use_cassette "data_validation/find_feed_source-ok" do
      DataValidation.find_feed_source(%{project: project, name: "tisseo"})
    end

    use_cassette "data_validation/validate_feed_source-ok" do
      assert :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
    end
  end

  test "retrives all feed sources" do
    {:ok, project} = use_cassette "data_validation/create_project-ok" do
      DataValidation.create_project(%{name: "transport"})
    end

    {:ok, feed_source} = use_cassette "data_validation/create_feed_source-ok" do
      name = "tisseo"
      url  = "https://data.toulouse-metropole.fr/api/v2/catalog/datasets/tisseo-gtfs/files/bd1298f158bc39ed9065e0c17ebb773b"
      DataValidation.create_feed_source(%{project: project, name: name, url: url})
    end

    use_cassette "data_validation/validate_feed_source-ok" do
      DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
    end

    {:ok, [%{latest_version_id: latest_version_id}]} = use_cassette "data_validation/list_feed_sources-ok" do
      DataValidation.list_feed_sources(%{project: project})
    end

    use_cassette "data_validation/find_feed_version-ok" do
      {:ok, %{namespace: namespace}} = DataValidation.find_feed_version(%{project: project, latest_version_id: latest_version_id})
      assert namespace == "njgv_blmzbjxrgkbuiyiwlrzpcd"
    end
  end
end
