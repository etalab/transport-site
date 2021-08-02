defmodule Transport.ModifiedAtCalculation do
  @moduledoc """
  An improved way to compute timestamp of modification for each resource.

  For the background, see:
  * https://github.com/etalab/transport-site/issues/1604
  * https://github.com/etalab/transport-site/issues/1645
  """
  import Ecto.Query, only: [from: 2]

  @doc """
  This method attempts to evaluate a timestamp of modification that
  is better than the meta-data we get from data gouv at the moment.

  To achieve this, we leverage the fact that the nightly crawler
  creates a `DB.LogsValidation` with a special "content hash as changed" text
  when a change is detected.

  This must then be used carefully, as the computation will only be as correct
  as the logs themselves, and also because after a while, `Transport.LogCleaner`
  removes those logs.
  """
  def compute_last_modified_at_based_on_content_hash_change(resource) do
    reason = DB.Resource.get_content_hash_changed_text()

    query =
      from(l in DB.LogsValidation,
        select: l.timestamp,
        where:
          l.resource_id == ^resource.id and
            l.skipped_reason == ^reason,
        order_by: {:desc, :timestamp},
        limit: 1
      )

    DB.Repo.one(query)
  end
end
