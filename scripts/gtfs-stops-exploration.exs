@moduledoc """
  This script is used to explore the GTFS data.


"""

# There is already plenty of code in Transport.GTFSData

# You can use the following to get a list of all the stops in a given area:

Transport.GTFSData.build_detailed({48.9,  , 2.4, 2.2})

# This will give you a map with all the stops in the given area, with their coordinates, name, etc and even the dataset id :

# %{
#   features: [
#     %{
#       geometry: %{coordinates: [2.373912, 48.844578], type: "Point"},
#       properties: %{
#         d_id: 54958,
#         d_title: "Réseau national TER SNCF",
#         stop_id: "StopArea:OCE87686006",
#         stop_location_type: 1,
#         stop_name: "Paris Gare de Lyon Hall 1 - 2"
#       },
#       type: "Feature"
#     },…
#       ],
#       type: "FeatureCollection"
#   }
