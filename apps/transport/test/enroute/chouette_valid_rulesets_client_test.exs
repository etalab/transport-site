defmodule Transport.EnRoute.ChouetteValidRulesetsClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias Transport.EnRoute.ChouetteValidRulesetsClient

  setup :verify_on_exit!

  @base_url "https://chouette-valid.enroute.mobi/api/rulesets"
  @fake_auth "Token token=fake_enroute_token"

  test "list rulesets" do
    response_body = [
      %{
        "id" => "2d9ffada-d923-40ee-8c76-02f262b1d8d5",
        "name" => "enRoute Starter-Kit",
        "slug" => "enroute:starter-kit:1",
        "definition" => "[]",
        "created_at" => "2024-07-05T14:41:19.933Z",
        "updated_at" => "2024-07-05T14:41:20.933Z"
      }
    ]

    Transport.Req.Mock
    |> expect(:get!, fn request ->
      expect_commons(request)

      assert URI.parse("") == request.url

      %Req.Response{status: 200, body: response_body}
    end)

    assert response_body == ChouetteValidRulesetsClient.list_rulesets()
  end

  test "get ruleset by slug" do
    name = "PAN - French Profile"
    slug = "pan:french_profile:1"
    definition = "[]"

    response_body =
      %{
        "id" => "2d9ffada-d923-40ee-8c76-02f262b1d8d5",
        "name" => name,
        "slug" => slug,
        "definition" => definition,
        "created_at" => "2024-07-05T14:41:19.933Z",
        "updated_at" => "2024-07-05T14:41:20.933Z"
      }

    Transport.Req.Mock
    |> expect(:get, fn request, [url: url] ->
      expect_commons(request)

      assert "/#{slug}" == url

      {:ok, %Req.Response{status: 200, body: response_body}}
    end)

    assert {:ok, response_body} == ChouetteValidRulesetsClient.get_ruleset(slug)
  end

  test "create ruleset" do
    name = "PAN - French Profile"
    slug = "pan:french_profile:1"
    definition = "[]"

    response_body =
      %{
        "id" => "2d9ffada-d923-40ee-8c76-02f262b1d8d5",
        "name" => name,
        "slug" => slug,
        "definition" => definition,
        "created_at" => "2024-07-05T14:41:19.933Z",
        "updated_at" => "2024-07-05T14:41:20.933Z"
      }

    Transport.Req.Mock
    |> expect(:request, fn request, [method: :post, url: "", json: json] ->
      expect_commons(request)

      assert name == json.ruleset.name
      assert slug == json.ruleset.slug
      assert definition == json.ruleset.definition

      {:ok, %Req.Response{status: 201, body: response_body}}
    end)

    assert {:ok, "2d9ffada-d923-40ee-8c76-02f262b1d8d5"} ==
             ChouetteValidRulesetsClient.create_ruleset(definition, name, slug)
  end

  test "update ruleset" do
    ruleset_id = "2d9ffada-d923-40ee-8c76-02f262b1d8d5"
    name = "PAN - French Profile"
    slug = "pan:french_profile:1"
    definition = "[]"

    response_body =
      %{
        "id" => ruleset_id,
        "name" => name,
        "slug" => slug,
        "definition" => definition,
        "created_at" => "2024-07-05T14:41:19.933Z",
        "updated_at" => "2025-09-10T18:34:43.644Z"
      }

    Transport.Req.Mock
    |> expect(:request, fn request, [method: :put, url: url, json: json] ->
      expect_commons(request)

      assert "/#{slug}" == url

      assert name == json.ruleset.name
      assert slug == json.ruleset.slug
      assert definition == json.ruleset.definition

      {:ok, %Req.Response{status: 200, body: response_body}}
    end)

    assert {:ok, "2d9ffada-d923-40ee-8c76-02f262b1d8d5"} ==
             ChouetteValidRulesetsClient.update_ruleset(definition, name, slug)
  end

  test "delete ruleset" do
    ruleset_id = "2d9ffada-d923-40ee-8c76-02f262b1d8d5"

    Transport.Req.Mock
    |> expect(:delete, fn request, [url: url] ->
      expect_commons(request)

      assert "/#{ruleset_id}.json" == url

      {:ok, %Req.Response{status: 200}}
    end)

    assert :ok == ChouetteValidRulesetsClient.delete_ruleset(ruleset_id)
  end

  defp expect_commons(request) do
    assert @fake_auth == request.options.auth
    assert @base_url == request.options.base_url
  end
end

defmodule Transport.EnRoute.ChouetteValidRulesetsClient.SlugsTest do
  use ExUnit.Case, async: true
  doctest Transport.EnRoute.ChouetteValidRulesetsClient.Slugs, import: true
end
