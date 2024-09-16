#! /usr/bin/env mix run

require Logger

resources =
  Transport.IRVE.Extractor.resources()
  |> Enum.take(2)

resources = Transport.IRVE.Extractor.download_and_parse_all(resources)

resources |> IO.inspect(IEx.inspect_opts())

# TODO: modifier `download_and_parse_all` pour récupérer le stream complet
# TODO: déverser ça dans un fichier groupé
# TODO: gérer les erreurs dans le flux
# TODO: collecter, au passage (`Stream` resource + accumulateur? sans agent si possible)
# TODO: générer deux fichiers
# TODO: importance de la traçabilité générale
# TODO: garder le code existant compatible (outils en place, utilisés)
