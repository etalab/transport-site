defmodule Transport.Test.Transport.Jobs.ConsolidateBNLCJobTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  use Oban.Testing, repo: DB.Repo
  import Mox
  import Swoosh.TestAssertions
  alias Transport.Jobs.ConsolidateBNLCJob

  @target_schema "etalab/schema-lieux-covoiturage"
  @tmp_path System.tmp_dir!() |> Path.join("bnlc.csv")

  doctest ConsolidateBNLCJob, import: true
  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Resources.Mock, Datagouvfr.Client.Resources.External)
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "datagouv_dataset_slugs" do
    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
        body = """
        dataset_url
        https://demo.data.gouv.fr/fr/datasets/foo/
        https://demo.data.gouv.fr/fr/datasets/bar
        https://demo.data.gouv.fr/fr/datasets/bar/
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert ["foo", "bar"] == ConsolidateBNLCJob.datagouv_dataset_slugs()
  end

  test "extract_dataset_details" do
    # foo is a 200 response including a resource with an appropriate schema
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/foo/", "", [], [follow_redirect: true] ->
      body = %{"slug" => "foo", "resources" => [%{"schema" => %{"name" => @target_schema}}]}
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
    end)

    # bar is a 200-response with a resource without a schema
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/bar/", "", [], [follow_redirect: true] ->
      body = %{"slug" => "bar", "resources" => [%{"format" => "csv"}]}
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
    end)

    # baz returns an error
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/baz/", "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
    end)

    assert %{
             errors: [
               %{
                 dataset_details: %{"resources" => [%{"format" => "csv"}], "slug" => "bar"},
                 error: :not_at_least_one_appropriate_resource
               },
               %{dataset_slug: "baz", error: :dataset_not_found}
             ],
             ok: [%{"resources" => [%{"schema" => %{"name" => @target_schema}}], "slug" => "foo"}]
           } == ConsolidateBNLCJob.extract_dataset_details(["foo", "bar", "baz"])
  end

  describe "format_errors" do
    test "it formats everything" do
      errors = %{
        dataset_errors: [
          %{error: :dataset_not_found, dataset_slug: "404-slug"},
          %{
            error: :not_at_least_one_appropriate_resource,
            dataset_details: %{"page" => "https://example.com/jdd", "title" => "JDD sans ressources"}
          }
        ],
        validation_errors: [
          {%{"page" => "https://example.com/jdd_erreur", "title" => "JDD avec erreurs"},
           %{"title" => "Ressource avec erreurs", "schema" => %{"name" => @target_schema}}}
        ],
        download_errors: [
          {:download,
           {%{"page" => "https://example.com/jdd_download_error", "title" => "JDD avec erreur de téléchargement"},
            %{"title" => "Ressource indisponible", "schema" => %{"name" => @target_schema}}}}
        ],
        decode_errors: [
          {:decode,
           {%{"page" => "https://example.com/jdd_decode_error", "title" => "JDD impossible à décoder"},
            %{"title" => "Ressource mal formatée", "schema" => %{"name" => @target_schema}}}}
        ]
      }

      assert """
             <h2>Erreurs liées aux jeux de données</h2>
             Le slug du jeu de données `404-slug` est introuvable via l'API<br/>Pas de ressources avec le schéma etalab/schema-lieux-covoiturage pour <a href=\"https://example.com/jdd\">JDD sans ressources</a>


             <h2>Ressources non valides par rapport au schéma etalab/schema-lieux-covoiturage</h2>
             Ressource `Ressource avec erreurs` (<a href="https://example.com/jdd_erreur">JDD avec erreurs</a>)


             <h2>Impossible de télécharger les ressources suivantes</h2>
             Ressource `Ressource indisponible` (<a href="https://example.com/jdd_download_error">JDD avec erreur de téléchargement</a>)


             <h2>Impossible de décoder les fichiers CSV suivants</h2>
             Ressource `Ressource mal formatée` (<a href="https://example.com/jdd_decode_error">JDD impossible à décoder</a>)\
             """ == ConsolidateBNLCJob.format_errors(errors)
    end

    test "nil when there are no errors" do
      assert nil ==
               ConsolidateBNLCJob.format_errors(%{
                 dataset_errors: [],
                 validation_errors: [],
                 download_errors: [],
                 decode_errors: []
               })
    end
  end

  test "valid_datagouv_resources" do
    datasets_details = [
      dataset_details = %{
        "resources" => [
          resource = %{
            "schema" => %{"name" => @target_schema},
            "url" => url = "https://example.com/file.csv"
          },
          # Ignored, not the expected schema
          %{"format" => "GTFS"},
          other_resource = %{
            "schema" => %{"name" => @target_schema},
            "url" => other_url = "https://example.com/other_file.csv"
          }
        ],
        "slug" => "foo"
      },
      # Another dataset where we will simulate a validation error (validator's fault)
      other_dataset_details = %{
        "resources" => [
          validation_error_resource = %{
            "schema" => %{"name" => @target_schema},
            "url" => file_error_url = "https://example.com/file_error.csv"
          }
        ],
        "slug" => "bar"
      }
    ]

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^url ->
      %{"has_errors" => false}
    end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^other_url ->
      %{"has_errors" => true}
    end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^file_error_url ->
      nil
    end)

    assert %{
             errors: [
               {:error, dataset_details, other_resource},
               {:validator_unavailable_error, other_dataset_details, validation_error_resource}
             ],
             ok: [{dataset_details, resource}]
           } == ConsolidateBNLCJob.valid_datagouv_resources(datasets_details)
  end

  test "download_resources" do
    dataset_detail = %{
      "resources" => [
        resource = %{
          "id" => resource_id = Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => url = "https://example.com/file.csv"
        }
      ],
      "slug" => "foo"
    }

    dataset_download_error_detail = %{
      "resources" => [
        resource_download_error = %{
          "id" => Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => download_error_url = "https://example.com/download_error.csv"
        }
      ],
      "slug" => "bar"
    }

    dataset_decode_error_detail = %{
      "resources" => [
        resource_decode_error = %{
          "id" => resource_decode_error_id = Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => decode_error_url = "https://example.com/decode_error.csv"
        }
      ],
      "slug" => "baz"
    }

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      body = """
      foo,bar
      1,2
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^download_error_url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 500, body: ""}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^decode_error_url, [], [follow_redirect: true] ->
      # Malformed CSV: unescaped double quotes: `""2"`
      body = """
      "foo","bar"
      "1",""2"
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    resources_details = [
      {dataset_detail, resource},
      {dataset_download_error_detail, resource_download_error},
      {dataset_decode_error_detail, resource_decode_error}
    ]

    assert %{
             errors: [
               {:download, {^dataset_download_error_detail, ^resource_download_error}},
               {:decode,
                {^dataset_decode_error_detail,
                 %{
                   "id" => ^resource_decode_error_id,
                   "csv_separator" => ?,,
                   "tmp_download_path" => tmp_decode_error_download_path,
                   "url" => ^decode_error_url
                 }}}
             ],
             ok: [
               {^dataset_detail,
                %{"id" => ^resource_id, "url" => ^url, "csv_separator" => ?,, "tmp_download_path" => tmp_download_path}}
             ]
           } = ConsolidateBNLCJob.download_resources(resources_details)

    assert String.ends_with?(tmp_download_path, "consolidate_bnlc_#{resource_id}")
    assert File.exists?(tmp_download_path)
    refute File.exists?(tmp_decode_error_download_path)
  end

  test "guess_csv_separator" do
    assert ?, ==
             ConsolidateBNLCJob.guess_csv_separator("""
             foo,bar
             1,2
             """)

    assert ?; ==
             ConsolidateBNLCJob.guess_csv_separator("""
             foo;bar
             1;2
             """)

    assert ?; ==
             ConsolidateBNLCJob.guess_csv_separator("""
             "foo";"bar"
             1;2
             """)
  end

  test "bnlc_csv_headers" do
    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv" ->
        body = """
        "foo","bar","baz","id_lieu"
        a,1,2,3
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert ["foo", "bar", "baz", "id_lieu"] == ConsolidateBNLCJob.bnlc_csv_headers()
  end

  test "consolidate_resources" do
    dataset_detail = %{
      "resources" => [
        resource = %{
          "id" => resource_id = Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => url = "https://example.com/file.csv"
        }
      ],
      "slug" => "foo",
      "id" => dataset_id = Ecto.UUID.generate()
    }

    other_dataset_detail = %{
      "resources" => [
        other_resource = %{
          "id" => other_resource_id = Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => other_url = "https://example.com/other_file.csv"
        }
      ],
      "slug" => "bar",
      "id" => other_dataset_id = Ecto.UUID.generate()
    }

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      # A CSV with BOM (byte order mark)
      body = """
      \uFEFFfoo,bar,baz,insee,id_local
      1,2,3,21231,1
      4,5,6,21231,2
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^other_url, [], [follow_redirect: true] ->
      body = """
      "foo";"bar";"baz";"insee";"id_local";"extra_col";"id_lieu"
      "a";"b";"c";"21231";"3";"its_a_trap";"not_falling_for_this"
      "d";"e";"f";"21231";"4";"should_be_ignored";"cant_mess_with_me"
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    resources_details = [{dataset_detail, resource}, {other_dataset_detail, other_resource}]
    assert %{errors: [], ok: res} = ConsolidateBNLCJob.download_resources(resources_details)

    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      2,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv" ->
        body = """
        "foo","bar","baz","id_lieu","insee","id_local"
        I,Love,CSV,3,21231,5
        Very,Much,So,4,21231,6
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert :ok == ConsolidateBNLCJob.consolidate_resources(res)

    assert [
             %{
               "foo" => "I",
               "bar" => "Love",
               "baz" => "CSV",
               "insee" => "21231",
               "id_local" => "5",
               "id_lieu" => "21231-5",
               "dataset_id" => "bnlc_github",
               "resource_id" => "bnlc_github"
             },
             %{
               "foo" => "Very",
               "bar" => "Much",
               "baz" => "So",
               "insee" => "21231",
               "id_local" => "6",
               "id_lieu" => "21231-6",
               "dataset_id" => "bnlc_github",
               "resource_id" => "bnlc_github"
             },
             %{
               "foo" => "1",
               "bar" => "2",
               "baz" => "3",
               "insee" => "21231",
               "id_local" => "1",
               "id_lieu" => "21231-1",
               "dataset_id" => dataset_id,
               "resource_id" => resource_id
             },
             %{
               "foo" => "4",
               "bar" => "5",
               "baz" => "6",
               "insee" => "21231",
               "id_local" => "2",
               "id_lieu" => "21231-2",
               "dataset_id" => dataset_id,
               "resource_id" => resource_id
             },
             %{
               "foo" => "a",
               "bar" => "b",
               "baz" => "c",
               "insee" => "21231",
               "id_local" => "3",
               "id_lieu" => "21231-3",
               "dataset_id" => other_dataset_id,
               "resource_id" => other_resource_id
             },
             %{
               "foo" => "d",
               "bar" => "e",
               "baz" => "f",
               "insee" => "21231",
               "id_local" => "4",
               "id_lieu" => "21231-4",
               "dataset_id" => other_dataset_id,
               "resource_id" => other_resource_id
             }
           ] == @tmp_path |> File.stream!() |> CSV.decode!(headers: true) |> Enum.to_list()

    # From https://datatracker.ietf.org/doc/html/rfc4180#section-2
    # > Each record is located on a separate line, delimited by a line break (CRLF)
    # We could change to just a newline, using the `delimiter` option:
    # https://hexdocs.pm/csv/CSV.html#encode/2
    assert """
           id_lieu,foo,bar,baz,insee,id_local,dataset_id,resource_id\r
           21231-5,I,Love,CSV,21231,5,bnlc_github,bnlc_github\r
           21231-6,Very,Much,So,21231,6,bnlc_github,bnlc_github\r
           21231-1,1,2,3,21231,1,#{dataset_id},#{resource_id}\r
           21231-2,4,5,6,21231,2,#{dataset_id},#{resource_id}\r
           21231-3,a,b,c,21231,3,#{other_dataset_id},#{other_resource_id}\r
           21231-4,d,e,f,21231,4,#{other_dataset_id},#{other_resource_id}\r
           """ == File.read!(@tmp_path)

    # Temporary files have been removed
    [{_, r1}, {_, r2}] = res
    refute r1 |> Map.fetch!("tmp_download_path") |> File.exists?()
    refute r2 |> Map.fetch!("tmp_download_path") |> File.exists?()
  end

  describe "perform" do
    test "simple success case, no errors" do
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
          body = """
          dataset_url
          https://demo.data.gouv.fr/fr/datasets/foo/
          https://demo.data.gouv.fr/fr/datasets/bar
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      foo_dataset_response = %{
        "id" => foo_dataset_id = Ecto.UUID.generate(),
        "slug" => "foo",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => foo_resource_id = Ecto.UUID.generate(),
            "url" => foo_url = "https://example.com/foo.csv"
          },
          # Should be ignored, irrelevant resource
          %{
            "id" => Ecto.UUID.generate(),
            "url" => "fake",
            "format" => "GTFS"
          }
        ]
      }

      bar_dataset_response = %{
        "id" => bar_dataset_id = Ecto.UUID.generate(),
        "slug" => "bar",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => bar_resource_id = Ecto.UUID.generate(),
            "url" => bar_url = "https://example.com/bar.csv"
          }
        ]
      }

      # Calling the data.gouv.fr's API to get dataset details
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/foo/", "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(foo_dataset_response)}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/bar/", "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(bar_dataset_response)}}
      end)

      # Validating resources with the schema validator
      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^foo_url ->
        %{"has_errors" => false}
      end)

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^bar_url ->
        %{"has_errors" => false}
      end)

      # Fetching CSV content and storing files locally
      Transport.HTTPoison.Mock
      |> expect(:get, fn ^foo_url, [], [follow_redirect: true] ->
        body = """
        "foo";"bar";"baz";"insee";"id_local"
        "a";"b";"c";"21231";"1"
        "d";"e";"f";"21231";"2"
        """

        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^bar_url, [], [follow_redirect: true] ->
        # A CSV with BOM (byte order mark)
        body = """
        \uFEFFfoo,bar,baz,insee,id_local,extra_col,id_lieu
        1,2,3,21231,3,is_ignored,is_generated_again
        """

        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end)

      # Fetching the BNLC content hosted on GitHub
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        2,
        fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv" ->
          body = """
          "foo","bar","baz","insee","id_local"
          I,Love,CSV,21231,4
          Very,Much,So,21231,5
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      expect_s3_stream_upload()

      assert :ok == perform_job(ConsolidateBNLCJob, %{})

      assert_ok_email_sent()
      expect_job_scheduled_to_remove_file()

      # CSV content is fine
      assert """
             id_lieu,foo,bar,baz,insee,id_local,dataset_id,resource_id\r
             21231-4,I,Love,CSV,21231,4,bnlc_github,bnlc_github\r
             21231-5,Very,Much,So,21231,5,bnlc_github,bnlc_github\r
             21231-1,a,b,c,21231,1,#{foo_dataset_id},#{foo_resource_id}\r
             21231-2,d,e,f,21231,2,#{foo_dataset_id},#{foo_resource_id}\r
             21231-3,1,2,3,21231,3,#{bar_dataset_id},#{bar_resource_id}\r
             """ == File.read!(@tmp_path)
    end

    test "stops when the schema validator is down" do
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
          body = """
          dataset_url
          https://demo.data.gouv.fr/fr/datasets/foo/
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      dataset_response = %{
        "slug" => "foo",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => Ecto.UUID.generate(),
            "url" => foo_url = "https://example.com/foo.csv"
          },
          %{
            "schema" => %{"name" => @target_schema},
            "id" => Ecto.UUID.generate(),
            "url" => bar_url = "https://example.com/bar.csv"
          }
        ]
      }

      # Calling the data.gouv.fr's API to get dataset details
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/foo/", "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(dataset_response)}}
      end)

      # Validating resources with the schema validator
      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^foo_url -> nil end)

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^bar_url ->
        %{"has_errors" => false}
      end)

      assert {:discard, "Cannot consolidate the BNLC because the TableSchema validator is not available"} ==
               perform_job(ConsolidateBNLCJob, %{})
    end

    test "when a resource is not valid" do
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
          body = """
          dataset_url
          https://demo.data.gouv.fr/fr/datasets/foo/
          https://demo.data.gouv.fr/fr/datasets/bar
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      foo_dataset_response = %{
        "id" => foo_dataset_id = Ecto.UUID.generate(),
        "slug" => "foo",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => foo_resource_id = Ecto.UUID.generate(),
            "url" => foo_url = "https://example.com/foo.csv"
          },
          # Should be ignored, irrelevant resource
          %{
            "id" => Ecto.UUID.generate(),
            "url" => "fake",
            "format" => "GTFS"
          }
        ]
      }

      bar_dataset_response = %{
        "id" => Ecto.UUID.generate(),
        "slug" => "bar",
        "title" => "Bar JDD",
        "page" => "https://data.gouv.fr/bar",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => Ecto.UUID.generate(),
            "url" => bar_url = "https://example.com/bar.csv",
            "title" => "Bar CSV"
          }
        ]
      }

      # Calling the data.gouv.fr's API to get dataset details
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/foo/", "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(foo_dataset_response)}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/bar/", "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(bar_dataset_response)}}
      end)

      # Validating resources with the schema validator
      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^foo_url ->
        %{"has_errors" => false}
      end)

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^bar_url ->
        %{"has_errors" => true}
      end)

      # Fetching CSV content and storing files locally
      Transport.HTTPoison.Mock
      |> expect(:get, fn ^foo_url, [], [follow_redirect: true] ->
        body = """
        "foo";"bar";"baz";"insee";"id_local"
        "a";"b";"c";"21231";"1"
        "d";"e";"f";"21231";"2"
        """

        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end)

      # Fetching the BNLC content hosted on GitHub
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        2,
        fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv" ->
          body = """
          "foo","bar","baz","insee","id_local"
          I,Love,CSV,21231,3
          Very,Much,So,21231,4
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      expect_s3_stream_upload()

      assert :ok == perform_job(ConsolidateBNLCJob, %{})

      assert_ko_email_sent()

      expect_job_scheduled_to_remove_file()

      assert """
             id_lieu,foo,bar,baz,insee,id_local,dataset_id,resource_id\r
             21231-3,I,Love,CSV,21231,3,bnlc_github,bnlc_github\r
             21231-4,Very,Much,So,21231,4,bnlc_github,bnlc_github\r
             21231-1,a,b,c,21231,1,#{foo_dataset_id},#{foo_resource_id}\r
             21231-2,d,e,f,21231,2,#{foo_dataset_id},#{foo_resource_id}\r
             """ == File.read!(@tmp_path)
    end
  end

  test "replace_file_on_datagouv" do
    File.write!(@tmp_path, "fake_content")

    expect_datagouv_upload_file_http_call()

    ConsolidateBNLCJob.replace_file_on_datagouv()

    refute File.exists?(@tmp_path)
  end

  test "perform and update file on data.gouv.fr" do
    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
        %HTTPoison.Response{status_code: 200, body: "dataset_url"}
      end
    )

    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      2,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv" ->
        body = """
        "foo","bar","baz","insee","id_local"
        I,Love,CSV,21231,3
        Very,Much,So,21231,4
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    expect_s3_stream_upload()
    expect_datagouv_upload_file_http_call()

    assert :ok == perform_job(ConsolidateBNLCJob, %{"action" => "datagouv_update"})

    assert_ok_email_sent()

    expect_job_scheduled_to_remove_file()

    refute File.exists?(@tmp_path)
  end

  describe "deleting a temporary file" do
    test "perform with a wrong filename" do
      assert {:discard, ~s[Cannot delete file, unexpected filename: "foo"]} ==
               perform_job(ConsolidateBNLCJob, %{"action" => "delete_s3_file", "filename" => "foo"})
    end

    test "perform with an appropriate filename" do
      filename = "bnlc-#{Ecto.UUID.generate()}"

      Transport.ExAWS.Mock
      |> expect(:request!, fn %ExAws.Operation.S3{} = operation ->
        assert %ExAws.Operation.S3{
                 bucket: "transport-data-gouv-fr-on-demand-validation-test",
                 path: ^filename,
                 http_method: :delete,
                 service: :s3
               } = operation

        :ok
      end)

      assert :ok == perform_job(ConsolidateBNLCJob, %{"action" => "delete_s3_file", "filename" => filename})
    end
  end

  defp expect_s3_stream_upload do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.S3.Upload{
                              src: %File.Stream{},
                              bucket: "transport-data-gouv-fr-on-demand-validation-test",
                              path: path,
                              opts: [acl: :public_read],
                              service: :s3
                            } ->
      assert path =~ ~r"^bnlc-.*\.csv$"
    end)
  end

  defp expect_datagouv_upload_file_http_call do
    tmp_path = @tmp_path

    expected_url =
      "https://demo.data.gouv.fr/api/1/datasets/bnlc_fake_dataset_id/resources/bnlc_fake_resource_id/upload/"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :post,
                           ^expected_url,
                           args,
                           [{"content-type", "multipart/form-data"}, {"X-API-KEY", "fake-datagouv-api-key"}],
                           [follow_redirect: true] ->
      {:multipart, [{:file, ^tmp_path, {"form-data", [name: "file", filename: "bnlc.csv"]}, []}]} = args
      {:ok, %HTTPoison.Response{body: "", status_code: 200}}
    end)
  end

  defp expect_job_scheduled_to_remove_file do
    # A job has been enqueued and scheduled to delete the temporary file stored in the bucket
    assert [
             %Oban.Job{
               worker: "Transport.Jobs.ConsolidateBNLCJob",
               args: %{"action" => "delete_s3_file", "filename" => filename},
               scheduled_at: scheduled_at
             }
           ] = all_enqueued()

    assert_in_delta 7 * 4, DateTime.diff(scheduled_at, DateTime.utc_now(), :day), 1
    assert filename =~ ~r"^bnlc-.*\.csv$"
  end

  defp assert_ok_email_sent do
    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           subject: "[OK] Rapport de consolidation de la BNLC",
                           html_body: html_body
                         } ->
      assert html_body =~ ~r"^✅ La consolidation s'est déroulée sans erreurs"

      assert html_body =~
               ~r{🔗 <a href="https://transport-data-gouv-fr-on-demand-validation-test.cellar-c2.services.clever-cloud.com/bnlc-.*\.csv">Fichier consolidé</a>}
    end)
  end

  defp assert_ko_email_sent do
    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           subject: "[ERREUR] Rapport de consolidation de la BNLC",
                           html_body: html_body
                         } ->
      assert html_body =~
               ~s{<h2>Ressources non valides par rapport au schéma etalab/schema-lieux-covoiturage</h2>\nRessource `Bar CSV` (<a href="https://data.gouv.fr/bar">Bar JDD</a>)}

      assert html_body =~
               ~r{🔗 <a href="https://transport-data-gouv-fr-on-demand-validation-test.cellar-c2.services.clever-cloud.com/bnlc-.*\.csv">Fichier consolidé</a>}
    end)
  end
end
