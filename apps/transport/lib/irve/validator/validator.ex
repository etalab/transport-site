defmodule Transport.IRVE.Validator do
  @moduledoc """
  Central entry point for IRVE file validation (currently working on `DataFrame`).
  """

  def compute_validation(%Explorer.DataFrame{} = df) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    df
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_field_validation_columns(schema)
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_row_validation_column()
  end

  def validate(path) do
    # NOTES rapportées de ma branche de travail
    #
    # prendre le fichier:
    # probe: si c'est un zip, lever une erreur et arrêter
    # probe: si c'est un encoding latin1, convertir et noter
    # probe: voir les colonnes. si V1, lever une erreur spécifique
    # probe: voir si on a id_pdc_itinerance. lever une erreur sinon (trop différent)
    # probe: deviner le séparateur. Si ;, corriger en , et noter. Sinon, lever une erreur
    #        et arrêter
    # probe: vérifier les colonnes. Plein de possibilités. Colonnes qui manquent?  Colonnes
    #        en trop? Doublons?
    # (note: faire un profiling global de toutes les ressources dispos sur ce sujet, voir ce
    #  qui est utile à implémenter)
    # (on peut commencer strict : il faut "au moins exactement toutes les colonnes",
    #  et on droppe le reste avec un warning)
    # processing: supprimer les whitespaces (idéalement noter quand c'est fait avec
    #  un bitmask) en heading/trailing
    # processing: détecter les lignes cassées (pas le bon nombre de champs sur la ligne elle même)
    # à terme: persister: un JSON avec checksum du fichier, résultat général valid: true/false,
    #  valid row count, chemin vers dataframe et le dataframe réduit (bits) dans le format le plus
    #  compact possible. Pourquoi pas un zip avec les deux.

    path
    |> load_file_as_dataframe()
    |> compute_validation()
  end

  # NOTE: will be refactored at next validator iteration
  defp load_file_as_dataframe(path) do
    # NOTE: `infer_schema_length: 0` enforces strings everywhere
    case Explorer.DataFrame.from_csv(path, infer_schema_length: 0) do
      {:ok, df} -> df
      {:error, error} -> raise error
    end
  end

  @doc """
  Says from the dataframe output of compute_validation/1 if all rows are valid.
  """
  def full_file_valid?(%Explorer.DataFrame{} = df) do
    df["check_row_valid"]
    |> Explorer.Series.all?()
  end
end
