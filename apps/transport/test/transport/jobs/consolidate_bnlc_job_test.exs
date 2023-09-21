defmodule Transport.Test.Transport.Jobs.ConsolidateBNLCJobTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  use Oban.Testing, repo: DB.Repo
  import Mox
  alias Transport.Jobs.ConsolidateBNLCJob

  @target_schema "etalab/schema-lieux-covoiturage"
  @tmp_path System.tmp_dir!() |> Path.join("bnlc.csv")

  doctest ConsolidateBNLCJob, import: true
  setup :verify_on_exit!

  setup do
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
          {%{"page" => "https://example.com/jdd_download_error", "title" => "JDD avec erreur de téléchargement"},
           %{"title" => "Ressource indisponible", "schema" => %{"name" => @target_schema}}}
        ]
      }

      assert """
             <h2>Erreurs liées aux jeux de données</h2>
             Le slug du jeu de données `404-slug` est introuvable via l'API
             Pas de ressources avec le schéma etalab/schema-lieux-covoiturage pour <a href=\"https://example.com/jdd\">JDD sans ressources</a>


             <h2>Ressources non valides par rapport au schéma etalab/schema-lieux-covoiturage</h2>
             Ressource `Ressource avec erreurs` (<a href="https://example.com/jdd_erreur">JDD avec erreurs</a>)


             <h2>Impossible de télécharger les ressources suivantes</h2>
             Ressource `Ressource indisponible` (<a href="https://example.com/jdd_download_error">JDD avec erreur de téléchargement</a>)\
             """ == ConsolidateBNLCJob.format_errors(errors)
    end

    test "nil when there are no errors" do
      assert nil == ConsolidateBNLCJob.format_errors(%{dataset_errors: [], validation_errors: [], download_errors: []})
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
               {:validation_error, other_dataset_details, validation_error_resource}
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

    dataset_error_detail = %{
      "resources" => [
        resource_error = %{
          "id" => Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => error_url = "https://example.com/other_file.csv"
        }
      ],
      "slug" => "bar"
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
    |> expect(:get, fn ^error_url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 500, body: ""}}
    end)

    resources_details = [{dataset_detail, resource}, {dataset_error_detail, resource_error}]

    assert %{
             errors: [{^dataset_error_detail, ^resource_error}],
             ok: [
               {^dataset_detail,
                %{"id" => ^resource_id, "url" => ^url, "csv_separator" => ?,, "tmp_download_path" => tmp_download_path}}
             ]
           } = ConsolidateBNLCJob.download_resources(resources_details)

    assert String.ends_with?(tmp_download_path, "consolidate_bnlc_#{resource_id}")
    assert File.exists?(tmp_download_path)
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
        "foo","bar","baz"
        a,1,2
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert ["foo", "bar", "baz"] == ConsolidateBNLCJob.bnlc_csv_headers()
  end

  test "consolidate_resources" do
    dataset_detail = %{
      "resources" => [
        resource = %{
          "id" => Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => url = "https://example.com/file.csv"
        }
      ],
      "slug" => "foo"
    }

    other_dataset_detail = %{
      "resources" => [
        other_resource = %{
          "id" => Ecto.UUID.generate(),
          "schema" => %{"name" => @target_schema},
          "url" => other_url = "https://example.com/other_file.csv"
        }
      ],
      "slug" => "bar"
    }

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      body = """
      foo,bar,baz
      1,2,3
      4,5,6
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^other_url, [], [follow_redirect: true] ->
      body = """
      "foo";"bar";"baz"
      "a";"b";"c"
      "d";"e";"f"
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
        "foo","bar","baz"
        I,Love,CSV
        Very,Much,So
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert :ok == ConsolidateBNLCJob.consolidate_resources(res)

    assert [
             %{"foo" => "I", "bar" => "Love", "baz" => "CSV"},
             %{"foo" => "Very", "bar" => "Much", "baz" => "So"},
             %{"foo" => "1", "bar" => "2", "baz" => "3"},
             %{"foo" => "4", "bar" => "5", "baz" => "6"},
             %{"foo" => "a", "bar" => "b", "baz" => "c"},
             %{"foo" => "d", "bar" => "e", "baz" => "f"}
           ] == @tmp_path |> File.stream!() |> CSV.decode!(headers: true) |> Enum.to_list()

    # From https://datatracker.ietf.org/doc/html/rfc4180#section-2
    # > Each record is located on a separate line, delimited by a line break (CRLF)
    # We could change to just a newline, using the `delimiter` option:
    # https://hexdocs.pm/csv/CSV.html#encode/2
    assert """
           foo,bar,baz\r
           I,Love,CSV\r
           Very,Much,So\r
           1,2,3\r
           4,5,6\r
           a,b,c\r
           d,e,f\r
           """ = File.read!(@tmp_path)

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
        "slug" => "foo",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => Ecto.UUID.generate(),
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
        "slug" => "bar",
        "resources" => [
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
        "foo";"bar";"baz"
        "a";"b";"c"
        "d";"e";"f"
        """

        {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^bar_url, [], [follow_redirect: true] ->
        body = """
        foo,bar,baz
        1,2,3
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
          "foo","bar","baz"
          I,Love,CSV
          Very,Much,So
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr" = _display_name,
                               "contact@transport.beta.gouv.fr" = _from,
                               "deploiement@transport.beta.gouv.fr" = _to,
                               "contact@transport.beta.gouv.fr" = _reply_to,
                               "Rapport de consolidation de la BNLC" = _subject,
                               "",
                               html_part ->
        assert html_part == "✅ La consolidation s'est déroulée sans erreurs"
        :ok
      end)

      assert :ok == perform_job(ConsolidateBNLCJob, %{})

      assert """
             foo,bar,baz\r
             I,Love,CSV\r
             Very,Much,So\r
             a,b,c\r
             d,e,f\r
             1,2,3\r
             """ = File.read!(@tmp_path)
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
        "slug" => "foo",
        "resources" => [
          %{
            "schema" => %{"name" => @target_schema},
            "id" => Ecto.UUID.generate(),
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
        "foo";"bar";"baz"
        "a";"b";"c"
        "d";"e";"f"
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
          "foo","bar","baz"
          I,Love,CSV
          Very,Much,So
          """

          %HTTPoison.Response{status_code: 200, body: body}
        end
      )

      Transport.ExAWS.Mock
      |> expect(:request!, fn %ExAws.Operation.S3{} = operation ->
        assert %ExAws.Operation.S3{
                 bucket: "transport-data-gouv-fr-on-demand-validation-test",
                 path: path,
                 http_method: :put,
                 service: :s3
               } = operation

        assert path =~ ~r"^bnlc-.*\.csv$"
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr" = _display_name,
                               "contact@transport.beta.gouv.fr" = _from,
                               "deploiement@transport.beta.gouv.fr" = _to,
                               "contact@transport.beta.gouv.fr" = _reply_to,
                               "Rapport de consolidation de la BNLC" = _subject,
                               "",
                               html_part ->
        assert html_part =~
                 ~s{<h2>Ressources non valides par rapport au schéma etalab/schema-lieux-covoiturage</h2>\nRessource `Bar CSV` (<a href="https://data.gouv.fr/bar">Bar JDD</a>)}

        # Make sure a link is there

        :ok
      end)

      assert :ok == perform_job(ConsolidateBNLCJob, %{})

      assert """
             foo,bar,baz\r
             I,Love,CSV\r
             Very,Much,So\r
             a,b,c\r
             d,e,f\r
             """ = File.read!(@tmp_path)
    end
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
end
