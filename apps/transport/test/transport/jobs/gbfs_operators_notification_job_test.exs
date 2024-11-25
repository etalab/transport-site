defmodule Transport.Test.Transport.Jobs.GBFSOperatorsNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.GBFSOperatorsNotificationJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "perform" do
    test "no resources matching" do
      known_gbfs = insert(:resource, url: "https://example.com", format: "gbfs")
      refute Transport.GBFSMetadata.operator(known_gbfs.url) |> is_nil()

      assert GBFSOperatorsNotificationJob.relevant_feeds() |> Enum.empty?()
      assert :ok == perform_job(GBFSOperatorsNotificationJob, %{})

      assert_no_email_sent()
    end

    test "it works" do
      # Should be included: operator is not known
      %DB.Resource{id: gbfs_id} = insert(:resource, url: url = "https://404.fr", format: "gbfs")
      assert Transport.GBFSMetadata.operator(url) |> is_nil()

      # Ignored: GBFS resource is not available
      down_gbfs = insert(:resource, url: url = "https://404.fr", format: "gbfs", is_available: false)
      assert Transport.GBFSMetadata.operator(down_gbfs.url) |> is_nil()
      # Ignored: operator is known
      known_gbfs = insert(:resource, url: "https://example.com", format: "gbfs")
      refute Transport.GBFSMetadata.operator(known_gbfs.url) |> is_nil()
      # Ignored: not a GBFS
      insert(:resource, url: "https://404.fr/gtfs.zip", format: "GTFS")

      assert [%DB.Resource{id: ^gbfs_id}] = GBFSOperatorsNotificationJob.relevant_feeds()

      assert :ok == perform_job(GBFSOperatorsNotificationJob, %{})

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "contact@transport.data.gouv.fr"}],
                             reply_to: {"", "contact@transport.data.gouv.fr"},
                             subject: "Flux GBFS : opérateurs non détectés",
                             text_body: nil,
                             html_body: html_body
                           } ->
        assert html_body =~ ~r/pas possible de détecter automatiquement les opérateurs des flux GBFS/
        assert html_body =~ ~r|<li><a href="#{url}">#{url}</a></li>|
      end)
    end
  end
end
