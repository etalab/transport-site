defmodule Transport.EnRouteChouetteValidClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias Transport.EnRouteChouetteValidClient

  doctest Transport.EnRouteChouetteValidClient, import: true

  setup :verify_on_exit!

  @expected_headers [{"authorization", "Token token=fake_enroute_token"}]

  test "create a validation" do
    response_body =
      """
      {
        "id": "d8e2b6c2-b1e5-4890-84d4-9b761a445882",
        "rule_set": "enroute:starter-kit",
        "user_status": "pending",
        "include_schema": false,
        "created_at": "2024-07-05T14:41:19.933Z",
        "updated_at": "2024-07-05T14:41:19.933Z"
      }
      """

    url = "https://chouette-valid.enroute.mobi/api/validations"

    tmp_file = System.tmp_dir!() |> Path.join("enroute_validation_netex_#{Ecto.UUID.generate()}")

    expect(Transport.HTTPoison.Mock, :post!, fn ^url, {:multipart, parts}, headers ->
      assert @expected_headers == headers

      assert [
               {"validation[rule_set]", "enroute:starter-kit"},
               {"validation[include_schema]", "false"},
               {:file, tmp_file, {"form-data", [{:name, "validation[file]"}, {:filename, Path.basename(tmp_file)}]}, []}
             ] == parts

      %HTTPoison.Response{status_code: 201, body: response_body}
    end)

    assert "d8e2b6c2-b1e5-4890-84d4-9b761a445882" == EnRouteChouetteValidClient.create_a_validation(tmp_file)
  end

  describe "get a validation" do
    test "pending" do
      validation_id = "d8e2b6c2-b1e5-4890-84d4-9b761a445882"

      response_body =
        """
        {
          "id": "#{validation_id}",
          "rule_set": "enroute:starter-kit",
          "user_status": "pending",
          "include_schema": false,
          "started_at": "2024-07-05T14:41:20.680Z",
          "created_at": "2024-07-05T14:41:19.933Z",
          "updated_at": "2024-07-05T14:41:20.933Z"
        }
        """

      url = "https://chouette-valid.enroute.mobi/api/validations/#{validation_id}"

      expect(Transport.HTTPoison.Mock, :get!, fn ^url, headers ->
        assert @expected_headers == headers
        %HTTPoison.Response{status_code: 200, body: response_body}
      end)

      assert :pending == EnRouteChouetteValidClient.get_a_validation(validation_id)
    end

    test "successful" do
      validation_id = "d8e2b6c2-b1e5-4890-84d4-9b761a445882"

      response_body =
        """
        {
          "id": "#{validation_id}",
          "rule_set": "enroute:starter-kit",
          "user_status": "successful",
          "include_schema": false,
          "started_at": "2024-07-05T14:41:20.680Z",
          "ended_at": "2024-07-05T14:41:25.685Z",
          "created_at": "2024-07-05T14:41:19.933Z",
          "updated_at": "2024-07-05T14:41:20.933Z"
        }
        """

      url = "https://chouette-valid.enroute.mobi/api/validations/#{validation_id}"

      expect(Transport.HTTPoison.Mock, :get!, fn ^url, headers ->
        assert @expected_headers == headers
        %HTTPoison.Response{status_code: 200, body: response_body}
      end)

      assert {:successful, url, 5} == EnRouteChouetteValidClient.get_a_validation(validation_id)
    end

    test "warning" do
      validation_id = "d8e2b6c2-b1e5-4890-84d4-9b761a445882"

      response_body =
        """
        {
          "id": "#{validation_id}",
          "rule_set": "enroute:starter-kit",
          "user_status": "warning",
          "include_schema": false,
          "started_at": "2024-07-05T14:41:20.680Z",
          "ended_at": "2024-07-05T14:41:24.685Z",
          "created_at": "2024-07-05T14:41:19.933Z",
          "updated_at": "2024-07-05T14:41:20.933Z"
        }
        """

      url = "https://chouette-valid.enroute.mobi/api/validations/#{validation_id}"

      expect(Transport.HTTPoison.Mock, :get!, fn ^url, headers ->
        assert @expected_headers == headers
        %HTTPoison.Response{status_code: 200, body: response_body}
      end)

      assert {:warning, 4} == EnRouteChouetteValidClient.get_a_validation(validation_id)
    end

    test "failed" do
      validation_id = "d8e2b6c2-b1e5-4890-84d4-9b761a445882"

      response_body =
        """
        {
          "id": "#{validation_id}",
          "rule_set": "enroute:starter-kit",
          "user_status": "failed",
          "include_schema": false,
          "started_at": "2024-07-05T14:41:20.680Z",
          "ended_at": "2024-07-05T14:41:28.685Z",
          "created_at": "2024-07-05T14:41:19.933Z",
          "updated_at": "2024-07-05T14:41:20.933Z"
        }
        """

      url = "https://chouette-valid.enroute.mobi/api/validations/#{validation_id}"

      expect(Transport.HTTPoison.Mock, :get!, fn ^url, headers ->
        assert @expected_headers == headers
        %HTTPoison.Response{status_code: 200, body: response_body}
      end)

      assert {:failed, 8} == EnRouteChouetteValidClient.get_a_validation(validation_id)
    end
  end

  test "get messages" do
    response_body =
      """
      [
        {
          "code": "uic-operating-period",
          "message": "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
          "resource": {
            "id": "23504000009",
            "line": 665,
            "class": "OperatingPeriod",
            "column": 1,
            "filename": "RESOURCE.xml"
          },
          "criticity": "error"
        },
        {
          "code": "valid-day-bits",
          "message": "Mandatory attribute valid_day_bits not found",
          "resource": {
            "id": "23504000057",
            "line": 641,
            "class": "OperatingPeriod",
            "column": 1,
            "filename": "RESOURCE.xml"
          },
          "criticity": "error"
        },
        {
          "code": "frame-arret-resources",
          "message": "Tag frame_id doesn't match ''",
          "resource": {
            "id": "5030",
            "line": 424,
            "class": "Quay",
            "column": 5
          },
          "criticity": "error"
        }
      ]
      """

    validation_id = Ecto.UUID.generate()
    url = "https://chouette-valid.enroute.mobi/api/validations/#{validation_id}/messages"

    expect(Transport.HTTPoison.Mock, :get!, fn ^url, headers ->
      assert @expected_headers == headers
      %HTTPoison.Response{status_code: 200, body: response_body}
    end)

    {^url, messages} = EnRouteChouetteValidClient.get_messages(validation_id)
    assert length(messages) == 3
  end
end
