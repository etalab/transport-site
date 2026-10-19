defmodule Transport.IRVE.V3.StaticFixtureGenerator do
  @moduledoc """
  Seeded generator of realistic IRVE static v3 rows, conforming to the vendored schema.
  The same options always produce the same rows.

  Addresses are town halls sampled from the Annuaire de l'administration (DILA, Licence Ouverte), so that
  address, postal code, INSEE code and coordinates are consistent without pointing at private homes.
  Names, SIREN, AFIREV codes, phones and emails are fictitious.
  """

  @address_sample Application.app_dir(:transport, "priv/irve/mairie_addresses_sample.csv")
  @external_resource @address_sample

  @addresses @address_sample
             |> File.read!()
             |> NimbleCSV.RFC4180.parse_string()
             |> Enum.map(fn [adresse, code_postal, code_insee, commune, lat, lon] ->
               %{
                 adresse: adresse,
                 code_postal: code_postal,
                 code_insee: code_insee,
                 commune: commune,
                 latitude: String.to_float(lat),
                 longitude: String.to_float(lon)
               }
             end)

  # Values are drawn uniformly from each list: repetitions act as weights.
  # Connectors are atoms for dedicated columns, strings for `prise_type_autre`.
  @profiles %{
    ac: %{
      nb_pdc: [1, 2, 2, 2, 4, 6, 10],
      hardware: [{7.4, [:t2]}, {11, [:t2]}, {22, [:t2]}, {22, [:t2]}, {22, [:ef, :t2]}, {22, [:t2, "IEC_62196_T3C"]}],
      nom: ["Centre-ville", "Mairie", "Parking de la gare", "Supermarché"],
      condition_acces: ["Accès libre", "Accès libre", "Accès libre", "Accès réservé"],
      horaires: ["24/7", "24/7", "Mo-Sa 08:30-20:00", "Mo-Fr 08:00-19:00; Sa 09:00-12:00"],
      gratuit: [false, false, true, nil],
      paiement_cb: [false, nil],
      cb_sans_contact: [true, false, nil],
      paiement_ad_hoc: [["qr_dynamique"], ["site_web"], nil],
      plug_and_charge: [nil],
      recharge_intelligente: [nil, nil, ["remote"], ["remote", "bidirectionnel"]],
      reservation: [false],
      accessibilite_pmr: ["Accessible mais non réservé PMR", "Réservé PMR", "Non accessible", "Accessibilité inconnue"],
      type_vehicule: [nil, nil, ["M1"], ["M1", "L"]],
      equipement_afir: [[], ["parking_eclaire"], ["parking_couvert"]],
      equipement_ocpi: [nil, ["SUPERMARKET"], ["PARKING_LOT"]],
      gabarit: [{nil, nil, nil, nil}, {nil, 2.0, nil, nil}]
    },
    dc: %{
      nb_pdc: [1, 2, 4, 6, 8, 12],
      # Two CCS cables on one point: 2 connectors, a single connector type.
      hardware: [{50, [:ccs, :chademo, :t2]}, {150, [:ccs]}, {150, [:ccs, :ccs]}, {300, [:ccs]}, {350, [:ccs]}],
      nom: ["Aire de recharge", "Hub de recharge"],
      # Stations behind a motorway toll count as reserved access.
      condition_acces: ["Accès libre", "Accès libre", "Accès libre", "Accès réservé"],
      horaires: ["24/7"],
      gratuit: [false],
      paiement_cb: [true],
      cb_sans_contact: [true],
      paiement_ad_hoc: [[], ["qr_dynamique"], ["qr_dynamique", "site_web"]],
      plug_and_charge: [nil, false, true],
      recharge_intelligente: [nil, ["remote"], ["remote", "preferences"]],
      reservation: [false],
      accessibilite_pmr: ["Accessible mais non réservé PMR", "Non accessible", "Accessibilité inconnue"],
      type_vehicule: [nil, ["M1"]],
      equipement_afir: [["restauration", "sanitaires"], ["parking_eclaire", "repos", "restauration", "sanitaires"]],
      equipement_ocpi: [nil, ["FUEL_STATION", "RESTAURANT"]],
      gabarit: [{nil, nil, nil, nil}]
    },
    poids_lourds: %{
      nb_pdc: [2, 4, 6],
      hardware: [{400, [:ccs]}, {1000, [:mcs, :ccs]}],
      nom: ["Pôle logistique"],
      condition_acces: ["Accès libre"],
      horaires: ["24/7"],
      gratuit: [false],
      paiement_cb: [true],
      cb_sans_contact: [true],
      paiement_ad_hoc: [[]],
      plug_and_charge: [false, true],
      recharge_intelligente: [["remote"]],
      reservation: [true],
      accessibilite_pmr: ["Non accessible"],
      type_vehicule: [["N2", "N3", "M3"]],
      equipement_afir: [["parking_eclaire", "repos", "restauration", "sanitaires"]],
      equipement_ocpi: [nil],
      gabarit: [{44, 4.5, 18.75, 2.55}]
    }
  }

  @profile_draw List.duplicate(:ac, 14) ++ List.duplicate(:dc, 5) ++ [:poids_lourds]
  @alphanum ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  @digits ~c"0123456789"
  @meters_per_degree 111_320

  @doc """
  Generates rows: maps keyed by schema field name, typed values, `nil` for empty cells.

  Options: `:seed`, `:stations` (each spans `nb_pdc` rows), `:networks` (distinct aménageurs/opérateurs),
  `:now` (upper bound for all dates).
  """
  def generate(opts \\ []) do
    opts = Keyword.validate!(opts, seed: 1, stations: 10, networks: 1, now: ~U[2026-10-01 00:00:00Z])

    # A dedicated process keeps the seeded `:rand` state away from the caller's.
    Task.async(fn ->
      :rand.seed(:exsss, opts[:seed])
      emsp_pool = for _ <- 1..8, do: "FR" <> random_string(@alphanum, 3)
      trigrams = Stream.repeatedly(fn -> random_string(@alphanum, 3) end) |> Stream.uniq() |> Enum.take(opts[:networks])
      networks = Enum.map(trigrams, &build_network(&1, emsp_pool))

      # Addresses only repeat once the sample is exhausted, to avoid spurious co-located stations.
      @addresses
      |> Enum.shuffle()
      |> Stream.cycle()
      |> Enum.take(opts[:stations])
      |> Enum.map_reduce(%{}, fn address, counters ->
        network = Enum.random(networks)
        key = {network["trigram"], address.code_insee}
        counters = Map.update(counters, key, 1, &(&1 + 1))
        {build_station(network, address, counters[key], opts[:now]), counters}
      end)
      |> elem(0)
      |> Enum.concat()
    end)
    |> Task.await(:infinity)
  end

  @doc """
  Serializes rows to CSV, columns in schema order, lists as JSON.
  """
  def to_csv(rows) do
    fields = field_names()
    lines = Enum.map(rows, fn row -> Enum.map(fields, &format_value(Map.fetch!(row, &1))) end)
    [fields | lines] |> NimbleCSV.RFC4180.dump_to_iodata() |> IO.iodata_to_binary()
  end

  def field_names do
    Transport.CachedFiles.read_json("irve-v3/schema-statique.json")
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  defp format_value(nil), do: ""
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp format_value(value) when is_list(value), do: Jason.encode!(value)
  defp format_value(%Date{} = value), do: Date.to_iso8601(value)
  defp format_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_value(value), do: to_string(value)

  defp build_network(trigram, emsp_pool) do
    amenageur = company_name()
    operateur = Enum.random([amenageur, company_name()])

    %{
      "trigram" => trigram,
      "nom_amenageur" => amenageur,
      "siren_amenageur" => siren(),
      "contact_amenageur" => Enum.random(["contact@#{slug(amenageur)}.example.com", nil]),
      "nom_operateur" => operateur,
      "contact_operateur" => "support@#{slug(operateur)}.example.com",
      # ARCEP range reserved for fiction (01 99 00 xx xx); AFIR format keeps the leading zero.
      "telephone_operateur" => "+33 019900" <> random_string(@digits, 4),
      "nom_enseigne" => hd(String.split(operateur)) <> " Recharge",
      "emsp" => Enum.random([nil, emsp_pool |> Enum.take_random(3) |> Enum.sort()]),
      "local_ids" => Enum.random([true, false]),
      "raccordement" => Enum.random(["Direct", "Indirect", nil])
    }
  end

  defp company_name do
    Enum.random(["Volt", "Watt", "Ohm", "Borne", "Kilow"]) <>
      Enum.random(["ia", "éo", "ys", "ance"]) <> " " <> Enum.random(["SAS", "SA", "SEM"])
  end

  defp slug(name),
    do:
      name
      |> String.split()
      |> hd()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^A-Za-z0-9]/, "")
      |> String.downcase()

  # 8 random digits followed by a Luhn check digit.
  defp siren do
    digits = for _ <- 1..8, do: :rand.uniform(10) - 1

    sum =
      digits
      |> Enum.with_index(fn d, i -> if rem(i, 2) == 1, do: Integer.digits(d * 2) |> Enum.sum(), else: d end)
      |> Enum.sum()

    Enum.join(digits ++ [rem(10 - rem(sum, 10), 10)])
  end

  defp build_station(network, address, seq, now) do
    kind = Enum.random(@profile_draw)
    profile = @profiles[kind]
    pick = fn key -> Enum.random(profile[key]) end
    suffix = address.code_insee <> String.pad_leading(Integer.to_string(seq), 3, "0")

    # Stations are mostly built with a single hardware model, with occasional extensions.
    main_hardware = pick.(:hardware)
    pdcs = for i <- 1..pick.(:nb_pdc), do: {i, Enum.random([main_hardware, main_hardware, pick.(:hardware)])}
    powers = Enum.map(pdcs, fn {_i, {power, _prises}} -> power end)
    accessibilities = for _ <- pdcs, do: pick.(:accessibilite_pmr)
    nb_places = Enum.random([length(pdcs), length(pdcs), nil])
    {masse, hauteur, longueur, largeur} = pick.(:gabarit)
    gratuit = pick.(:gratuit)
    # The station stands near its street access, not on the address point.
    {latitude, longitude} = offset(address, _meters = Enum.random(5..100))

    station =
      network
      |> Map.drop(["trigram", "local_ids"])
      |> Map.merge(%{
        "id_station_itinerance" => "FR#{network["trigram"]}P#{suffix}",
        "id_station_local" => local_id(network, "ST-" <> suffix),
        "nom_station" => "#{address.commune} - #{pick.(:nom)}",
        "adresse_station" => address.adresse,
        "complement_localisation" => Enum.random([nil, nil, "Niveau -1"]),
        "code_postal" => address.code_postal,
        "code_insee_commune" => address.code_insee,
        "station_latitude" => latitude,
        "station_longitude" => longitude,
        "nb_pdc" => length(pdcs),
        # Grid connection often caps the station below the sum of its points.
        "puissance_maximale_station_kw" =>
          max(Enum.max(powers), min(Enum.sum(powers), round(Enum.sum(powers) * Enum.random(5..10) / 10))),
        "condition_acces" => pick.(:condition_acces),
        "horaires" => pick.(:horaires),
        "nb_places" => nb_places,
        "nb_places_pmr" => nb_places_pmr(nb_places, accessibilities),
        "gabarit_masse_max_t" => masse,
        "gabarit_hauteur_max_m" => hauteur,
        "gabarit_longueur_max_m" => longueur,
        "gabarit_largeur_max_m" => largeur,
        "type_vehicule" => pick.(:type_vehicule),
        "type_vehicule_autre" => nil,
        "presence_borniste" => Enum.random([nil, false]),
        "equipement_afir" => pick.(:equipement_afir),
        "equipement_ocpi" => pick.(:equipement_ocpi),
        "equipement_autre" => nil,
        "num_pdl" => if(network["raccordement"] == "Direct", do: random_string(@digits, 14)),
        "enr" => Enum.random([true, false, nil]),
        # The schema describes payment per point, but it is uniform across a station in practice.
        "gratuit" => gratuit,
        "paiement_ad_hoc_autre" => nil,
        "complement_paiement" => nil
      })
      |> Map.merge(payment_fields(gratuit, pick, network))

    commissioning = Date.add(DateTime.to_date(now), -Enum.random(30..(365 * 8)))

    for {{i, {power, prises}}, accessibilite} <- Enum.zip(pdcs, accessibilities) do
      mise_en_service = Enum.random([commissioning, commissioning, nil])
      connectors = connector_fields(prises)

      station
      |> Map.merge(connectors)
      |> Map.merge(%{
        "id_pdc_itinerance" => "FR#{network["trigram"]}E#{suffix}#{i}",
        "id_pdc_local" => local_id(network, "PDC-#{suffix}#{i}"),
        "puissance_nominale_kw" => power,
        "plug_and_charge" => pick.(:plug_and_charge),
        "recharge_intelligente" => pick.(:recharge_intelligente),
        "recharge_intelligente_autre" => nil,
        "tarif_ids" =>
          if(station["gratuit"] != true, do: tarif_ids(network["trigram"], connectors["courant_dc"], power)),
        "reservation" => pick.(:reservation),
        "accessibilite_pmr" => accessibilite,
        "date_mise_en_service" => mise_en_service,
        "horodatage_maj" => random_datetime(mise_en_service || commissioning, now)
      })
    end
  end

  defp connector_fields(prises) do
    %{
      "nb_connecteurs" => length(prises),
      "prise_type_ef" => :ef in prises,
      "prise_type_2" => :t2 in prises,
      "prise_type_combo_ccs" => :ccs in prises,
      "prise_type_chademo" => :chademo in prises,
      "prise_type_mcs" => :mcs in prises,
      "prise_type_autre" => Enum.filter(prises, &is_binary/1),
      "courant_ac" => Enum.any?(prises, &(&1 in [:ef, :t2] or is_binary(&1))),
      "courant_dc" => Enum.any?(prises, &(&1 in [:ccs, :chademo, :mcs]))
    }
  end

  # Moves the point by `meters` in a random direction, rounded to 6 decimals (~10 cm).
  defp offset(%{latitude: lat, longitude: lon}, meters) do
    angle = :rand.uniform() * 2 * :math.pi()
    dlat = meters * :math.cos(angle) / @meters_per_degree
    dlon = meters * :math.sin(angle) / (@meters_per_degree * :math.cos(lat * :math.pi() / 180))
    {Float.round(lat + dlat, 6), Float.round(lon + dlon, 6)}
  end

  # Payment means do not apply to permanently free charging.
  defp payment_fields(true = _gratuit, _pick, _network),
    do: %{"paiement_cb" => nil, "cb_sans_contact" => nil, "paiement_ad_hoc" => nil, "abonnement" => nil}

  defp payment_fields(_gratuit, pick, network) do
    %{
      "paiement_cb" => pick.(:paiement_cb),
      "cb_sans_contact" => pick.(:cb_sans_contact),
      "paiement_ad_hoc" => pick.(:paiement_ad_hoc),
      "abonnement" => if(network["emsp"], do: true)
    }
  end

  defp local_id(%{"local_ids" => true}, id), do: id
  defp local_id(_network, _id), do: nil

  # Counted only when every point's accessibility is known.
  defp nb_places_pmr(nil, _accessibilities), do: nil

  defp nb_places_pmr(_nb_places, accessibilities) do
    if "Accessibilité inconnue" in accessibilities,
      do: nil,
      else: Enum.count(accessibilities, &(&1 in ["Accessible mais non réservé PMR", "Réservé PMR"]))
  end

  # An upcoming tariff can be announced alongside the current one.
  defp tarif_ids(trigram, courant_dc, power) do
    base = "FR#{trigram}T#{if courant_dc, do: "DC", else: "AC"}#{round(power)}"
    Enum.random([[base], [base], [base], [base, base <> "V2"]])
  end

  defp random_datetime(%Date{} = since, now) do
    earliest = max(DateTime.to_unix(DateTime.new!(since, ~T[00:00:00])), DateTime.to_unix(now) - 400 * 86_400)
    DateTime.from_unix!(Enum.random(earliest..DateTime.to_unix(now)))
  end

  defp random_string(alphabet, length), do: for(_ <- 1..length, into: "", do: <<Enum.random(alphabet)>>)
end
