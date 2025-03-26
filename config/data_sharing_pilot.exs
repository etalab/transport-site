import Config

config :transport,
  data_sharing_pilot_dataset_custom_tag: "repartage_donnees",
  data_sharing_pilot_eligible_datagouv_organization_ids: [
    # transport.data.gouv.fr
    "5abca8d588ee386ee6ece479",
    # Google Maps
    "63fdfe4f4cd1c437ac478323",
    # Transit
    "5c9a6477634f4133c7a5fc01",
    # Citymapper / Via
    "5f7cade93fb405c7d8f6d554",
    # Apple Inc.
    "67b7aef304c5820ea7068341"
  ]
