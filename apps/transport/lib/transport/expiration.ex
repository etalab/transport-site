defmodule Transport.Expiration do
  @moduledoc """
  Shared utilities for expiration notification jobs.

  Centralizes delays configuration, date calculations, GTFS dataset queries,
  and French delay string formatting.

  Used by:
  - `Transport.Jobs.ExpirationNotificationJob` (reuser digests)
  - `Transport.Jobs.ExpirationAdminProducerNotificationJob` (producer/admin notifications)
  - `Transport.AdminNotifier` and `Transport.UserNotifier` (email formatting)
  """
  import Ecto.Query

  @type delay :: integer()
  @type dataset_ids :: [integer()]

  # Delays for reusers (daily digest)
  @reuser_delays [-30, -7, 0, 7, 14]
  # Delays for producers/admins (more granular notifications)
  @producer_admin_delays [-90, -60, -45, -30, -15, -7, -3, 0, 7, 14]

  @doc """
  Returns the list of delays used for reuser expiration notifications.

  ## Example
      iex> reuser_delays()
      [-30, -7, 0, 7, 14]
  """
  @spec reuser_delays() :: [delay()]
  def reuser_delays, do: @reuser_delays

  @doc """
  Returns the sorted list of delays used for producer/admin expiration notifications.

  ## Example
      iex> producer_admin_delays()
      [-90, -60, -45, -30, -15, -7, -3, 0, 7, 14]
  """
  @spec producer_admin_delays() :: [delay()]
  def producer_admin_delays, do: @producer_admin_delays |> Enum.uniq() |> Enum.sort()

  @doc """
  Calculates a map of delays to their corresponding dates.

  ## Example
      iex> delays_and_dates(~D[2024-05-21], [-7, 0, 7])
      %{-7 => ~D[2024-05-14], 0 => ~D[2024-05-21], 7 => ~D[2024-05-28]}
  """
  @spec delays_and_dates(Date.t(), [delay()]) :: %{delay() => Date.t()}
  def delays_and_dates(%Date{} = date, delays) do
    Map.new(delays, fn delay -> {delay, Date.add(date, delay)} end)
  end

  @doc """
  Returns a human-readable French string describing the delay.

  The `verb` argument handles singular (:périmant) vs plural (:périment) forms.

  ## Examples
      iex> delay_str(0, :périmant)
      "périmant demain"
      iex> delay_str(2, :périmant)
      "périmant dans 2 jours"
      iex> delay_str(-1, :périmant)
      "périmé depuis hier"
      iex> delay_str(-1, :périment)
      "sont périmées depuis hier"
      iex> delay_str(-2, :périment)
      "sont périmées depuis 2 jours"
  """
  @spec delay_str(delay(), :périmant | :périment) :: String.t()
  def delay_str(0, verb), do: "#{verb} demain"
  def delay_str(1, verb), do: "#{verb} dans 1 jour"
  def delay_str(d, verb) when d >= 2, do: "#{verb} dans #{d} jours"
  def delay_str(-1, :périmant), do: "périmé depuis hier"
  def delay_str(-1, :périment), do: "sont périmées depuis hier"
  def delay_str(d, :périmant) when d <= -2, do: "périmés depuis #{-d} jours"
  def delay_str(d, :périment) when d <= -2, do: "sont périmées depuis #{-d} jours"

  @doc """
  Convenience function for singular form (`:périmant`).

  ## Examples
      iex> delay_str(0)
      "périmant demain"
      iex> delay_str(-1)
      "périmé depuis hier"
      iex> delay_str(-2)
      "périmés depuis 2 jours"
  """
  @spec delay_str(delay()) :: String.t()
  def delay_str(delay), do: delay_str(delay, :périmant)

  @doc """
  Base query for GTFS datasets with expiration metadata.

  Joins datasets to their metadata using validators configured for expiration notifications,
  and filters to GTFS resources only.
  """
  @spec gtfs_with_expiration_metadata_query() :: Ecto.Query.t()
  def gtfs_with_expiration_metadata_query do
    validators = Transport.ValidatorsSelection.validators_for_feature(:expiration_notification)
    validator_names = Enum.map(validators, & &1.validator_name())

    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(validator_names)
    |> where([resource: r], r.format == "GTFS")
  end

  @doc """
  Returns dataset IDs grouped by delay for datasets expiring on target dates.

  Used by `ExpirationNotificationJob` for reuser digests.

  ## Example output
      %{-7 => [468, 600], 0 => [656, 919, 790, 931]}
  """
  @spec datasets_expiring_by_delay(Date.t(), [delay()]) :: %{delay() => dataset_ids()}
  def datasets_expiring_by_delay(%Date{} = reference_date, delays) do
    delays_map = delays_and_dates(reference_date, delays)
    dates_to_delays = Map.new(delays_map, fn {delay, date} -> {date, delay} end)
    target_dates = Map.values(delays_map)

    gtfs_with_expiration_metadata_query()
    |> where([metadata: m], fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) in ^target_dates)
    |> select([dataset: d, metadata: m], %{
      dataset_id: d.id,
      end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
    })
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.group_by(
      fn %{end_date: end_date} -> Map.fetch!(dates_to_delays, end_date) end,
      fn %{dataset_id: dataset_id} -> dataset_id end
    )
  end

  @doc """
  Returns datasets and their resources expiring on a specific date.

  Used by `ExpirationAdminProducerNotificationJob` for producer/admin notifications.

  Returns a list of tuples `{dataset, [resources]}` sorted by dataset ID.
  """
  @spec datasets_with_resources_expiring_on(Date.t()) :: [{DB.Dataset.t(), [DB.Resource.t()]}]
  def datasets_with_resources_expiring_on(%Date{} = date) do
    gtfs_with_expiration_metadata_query()
    |> where([metadata: m], fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) == ^date)
    |> select([dataset: d, resource: r], {d, r})
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.group_by(fn {dataset, _} -> dataset end, fn {_, resource} -> resource end)
    |> Enum.to_list()
    |> Enum.sort_by(&elem(&1, 0).id)
  end
end
