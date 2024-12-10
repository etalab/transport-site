defmodule Transport.GTFSRTTest do
  alias Transport.GTFSRT
  alias TransitRealtime.{TimeRange, TranslatedString}
  use ExUnit.Case, async: true
  import Mox
  import ExUnit.CaptureLog
  setup :verify_on_exit!

  @sample_file "#{__DIR__}/../fixture/files/bibus-brest-gtfs-rt-alerts.pb"
  @url "https://example.com/gtfs-rt"

  doctest GTFSRT, import: true

  describe "decode_remote_feed" do
    test "it works" do
      setup_gtfs_rt_feed(@url)
      {:ok, feed} = GTFSRT.decode_remote_feed(@url)
      message = feed.entity |> List.first()

      assert message.id == "2ea09850-74d9-4db7-a537-d97d821956e8"
      assert message.vehicle == nil
      assert message.trip_update == nil
      assert message.alert.cause == :CONSTRUCTION

      assert message.alert.description_text.translation |> List.first() |> Map.get(:text) =~
               ~r/Prolongation des travaux/
    end

    test "cannot decode Protobuf" do
      setup_http_response(@url, {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"foo": 42})}})

      {{:error, "Could not decode Protobuf"}, _} = with_log(fn -> GTFSRT.decode_remote_feed(@url) end)
    end

    test "502 HTTP status code" do
      setup_http_response(@url, {:ok, %HTTPoison.Response{status_code: 502, body: ""}})

      assert {:error, "Got a non 200 HTTP status code: 502"} == GTFSRT.decode_remote_feed(@url)
    end

    test "HTTPoison error" do
      reason =
        {:tls_alert,
         {:certificate_expired,
          ~c"TLS client: In state certify at ssl_handshake.erl:2065 generated CLIENT ALERT: Fatal - Certificate Expired\n"}}

      setup_http_response(@url, {:error, %HTTPoison.Error{reason: reason}})

      {:error, reason} = GTFSRT.decode_remote_feed(@url)
      assert reason =~ ~r"^Got an HTTP error:"
    end
  end

  test "timestamp" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)
    assert GTFSRT.timestamp(feed) == ~U[2021-12-16 15:29:02Z]
  end

  test "count_entities" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)
    assert %{service_alerts: 12, trip_updates: 0, vehicle_positions: 0} == GTFSRT.count_entities(feed)
  end

  test "service_alerts" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)
    assert GTFSRT.has_service_alerts?(feed)
    assert Enum.count(GTFSRT.service_alerts(feed)) == 12
  end

  test "trip_updates" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)
    assert Enum.empty?(GTFSRT.trip_updates(feed))
  end

  test "vehicle_positions" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)
    assert Enum.empty?(GTFSRT.vehicle_positions(feed))
  end

  test "fetch_translation" do
    assert GTFSRT.fetch_translation(
             %TranslatedString.Translation{language: "fr", text: "bonjour"},
             "fr"
           ) == "bonjour"

    assert GTFSRT.fetch_translation(%TranslatedString.Translation{language: nil, text: "bonjour"}, "fr") ==
             "bonjour"

    assert GTFSRT.fetch_translation(
             %TranslatedString.Translation{language: "fr", text: "bonjour"},
             "es"
           ) == nil
  end

  test "best_translation" do
    assert GTFSRT.best_translation(
             %TranslatedString{
               translation: [%TranslatedString.Translation{language: "fr", text: "bonjour"}]
             },
             "fr"
           ) == "bonjour"

    assert GTFSRT.best_translation(
             %TranslatedString{
               translation: [
                 %TranslatedString.Translation{language: "fr", text: "bonjour"},
                 %TranslatedString.Translation{language: "en", text: "hello"}
               ]
             },
             "en"
           ) == "hello"

    assert GTFSRT.best_translation(
             %TranslatedString{
               translation: [
                 %TranslatedString.Translation{language: "fr", text: "bonjour"},
                 %TranslatedString.Translation{language: "en", text: "hello"}
               ]
             },
             "fr"
           ) == "bonjour"

    assert GTFSRT.best_translation(
             %TranslatedString{
               translation: [%TranslatedString.Translation{language: nil, text: "bonjour"}]
             },
             "fr"
           ) == "bonjour"
  end

  test "current?" do
    assert GTFSRT.current?(timerange(-5, nil))
    assert GTFSRT.current?(timerange(-5, 5))
    assert GTFSRT.current?(timerange(nil, 5))
    refute GTFSRT.current?(timerange(-10, -5))
    refute GTFSRT.current?(timerange(10, nil))
    refute GTFSRT.current?(timerange(10, 20))
  end

  test "active?" do
    assert GTFSRT.active?([])
    assert GTFSRT.active?([timerange(nil, 5)])

    assert GTFSRT.active?([
             timerange(-10, -5),
             timerange(nil, 5)
           ])

    refute GTFSRT.active?([timerange(-10, -5)])
  end

  test "current_active_period" do
    assert GTFSRT.current_active_period([
             timerange(-10, -5)
           ]) == nil

    %{start: start, end: end_date} = tr = timerange(-10, 5)

    assert GTFSRT.current_active_period([tr]) == %{
             start: start |> DateTime.from_unix!(),
             end: end_date |> DateTime.from_unix!()
           }
  end

  test "service_alerts_for_display" do
    setup_gtfs_rt_feed(@url)
    {:ok, feed} = GTFSRT.decode_remote_feed(@url)

    assert %{
             cause: :CONSTRUCTION,
             current_active_period: nil,
             description_text:
               "MAJ 22/11, L 45, Prolongation des travaux rue de Kermaria, déviation en place jusqu'au 24 décembre.\nArrêts non desservis : Pen ar C'Hleuz et Kermaria\nArrêt de report : poteau provisoire",
             effect: :DETOUR,
             header_text: "L 45 Prolongation des travaux rue de Kermaria jusqu'au 24/12",
             is_active: false,
             url: "https://www.bibus.fr/deviation/20265cf9-6a99-403e-9ddb-4290b852c00a.pdf"
           } == feed |> GTFSRT.service_alerts_for_display() |> List.first()
  end

  @tag :ci_only_on_mondays
  test ".proto file is up-to-date" do
    normalize_whitespace = fn value ->
      String.trim(Regex.replace(~r/\s*/u, value, ""))
    end

    remote_content =
      HTTPoison.get!("https://raw.githubusercontent.com/google/transit/master/gtfs-realtime/proto/gtfs-realtime.proto").body

    local_content = File.read!("#{__DIR__}/../../lib/transport/protobuf/gtfs-realtime.proto")

    assert normalize_whitespace.(remote_content) == normalize_whitespace.(local_content),
           "Protobuf file seems to have been updated. Consider updating it. See https://github.com/google/transit/tree/master/gtfs-realtime/proto and https://github.com/etalab/transport-site/issues/3891"
  end

  def timerange(start_date, end_date) do
    %TimeRange{start: unix_seconds_delta(start_date), end: unix_seconds_delta(end_date)}
  end

  defp unix_seconds_delta(nil), do: nil

  defp unix_seconds_delta(seconds) when is_integer(seconds) do
    DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.to_unix()
  end

  defp setup_http_response(url, response) do
    Transport.HTTPoison.Mock |> expect(:get, fn ^url, [], follow_redirect: true -> response end)
  end

  defp setup_gtfs_rt_feed(url) do
    setup_http_response(url, {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@sample_file)}})
  end
end
