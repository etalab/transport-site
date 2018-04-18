defmodule Transport.DataValidation.Aggregates.Dataset.Validation do
  @moduledoc """
  Dataset validation contains a dataset's validation results.
  """

  defstruct [
    :issue_type,
    :object_id,
    :object_name,
    :related_object_id,
    :severity
  ]

  @type t :: %__MODULE__{
          issue_type: String.t(),
          object_id: String.t(),
          object_name: String.t(),
          related_object_id: String.t(),
          severity: String.t()
        }
end
