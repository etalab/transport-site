defmodule Transport.NotificationReason do
  @moduledoc """
  Provides common code for notification reasons used in DB.NotificationSubscription and DB.Notification.
  """

  # Rules explanations for reasons:
  # 1. scope: reasons are scoped either to a specific dataset or to the platform.
  # (In some cases for reusers, «platform» means scoped to followed datasets, not all datasets.)
  # 2. possible roles: reasons can be subscribed to by either producers or reusers.
  # 3. disallow_subscription: some reasons can’t be subscribed to,
  # but they exist because they are valid for notifications.
  # (In this case, it’s the platform that decides when to send them, without the user subscribing to them.)
  # 4. hide_from_user: some reasons are hidden from the user interface, but can be subscribed in CLI or backoffice.

  import TransportWeb.Gettext, only: [dgettext: 2]

  # TODO : undup?
  @possible_roles [:producer, :reuser]

  @reasons_rules %{
    expiration: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    dataset_with_error: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    resource_unavailable: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    resources_changed: %{
      scope: :dataset,
      possible_roles: [:reuser]
    },
    new_dataset: %{
      scope: :platform,
      possible_roles: [:reuser]
    },
    datasets_switching_climate_resilience_bill: %{
      scope: :platform,
      possible_roles: [:reuser],
      hide_from_user: [:reuser]
    },
    daily_new_comments: %{
      scope: :platform,
      possible_roles: [:producer, :reuser],
      hide_from_user: [:producer]
    },
    dataset_now_on_nap: %{
      scope: :dataset,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    periodic_reminder_producers: %{
      scope: :platform,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    promote_producer_space: %{
      scope: :platform,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    promote_reuser_space: %{
      scope: :platform,
      possible_roles: [:reuser],
      disallow_subscription: true
    },
    warn_user_inactivity: %{
      scope: :platform,
      possible_roles: [:producer, :reuser],
      disallow_subscription: true
    }
  }

  @all_reasons @reasons_rules |> Map.keys()

  # https://elixirforum.com/t/using-module-attributes-in-typespec-definitions-to-reduce-duplication/42374/2
  # TODO : dedup roles !
  types = Enum.reduce(@possible_roles, &{:|, [], [&1, &2]})
  @type role :: unquote(types)
  types = Enum.reduce(@all_reasons, &{:|, [], [&1, &2]})
  @type reason :: unquote(types)

  @spec all_reasons :: [reason()]
  def all_reasons do
    @all_reasons
  end

  @doc """
  This method provides a consistent manner to reference a `Transport.NotificationReason.reason`.
  This is useful when searching for code related to a reason, as it allows you to easily
  find all references to a particular reason.
  *
  The custom type `reason` helps us be safer at compile time, by preventing us from accidentally
  passing in an invalid reason value.
  """
  @spec reason(reason()) :: reason()
  def reason(reason) when reason in @all_reasons, do: reason

  @doc """
  This is also used in DB.Notification, but not for now in DB.NotificationSubscription.
  """

  @spec possible_roles() :: [role()]
  def possible_roles, do: @possible_roles

  @doc """
  iex> subscribable_reasons() |> MapSet.new()
  MapSet.new([:daily_new_comments, :dataset_with_error, :datasets_switching_climate_resilience_bill, :expiration, :new_dataset, :resource_unavailable, :resources_changed])
  """
  @spec subscribable_reasons :: [reason()]
  def subscribable_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{disallow_subscription: true}} -> false
      _ -> true
    end)
    |> Map.keys()
  end

  def unsuscribable_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{disallow_subscription: true}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @doc """
  iex> reasons_for_role(:reuser) |> MapSet.new()
  MapSet.new([:daily_new_comments, :dataset_with_error, :datasets_switching_climate_resilience_bill, :expiration, :new_dataset, :promote_reuser_space, :resource_unavailable, :resources_changed, :warn_user_inactivity])
  """
  @spec reasons_for_role(role()) :: [reason()]
  def reasons_for_role(role) do
    @reasons_rules
    |> Map.filter(fn
      {_, %{possible_roles: possible_roles}} -> role in possible_roles
      _ -> false
    end)
    |> Map.keys()
  end

  @doc """
  iex> hidden_reasons_for_role(:reuser)
  [:datasets_switching_climate_resilience_bill]
  """
  @spec hidden_reasons_for_role(role()) :: [reason()]
  def hidden_reasons_for_role(role) do
    @reasons_rules
    |> Map.filter(fn
      {_, %{hide_from_user: hide_from_user}} -> role in hide_from_user
      _ -> false
    end)
    |> Map.keys()
  end

  @spec reasons_related_to_datasets :: [reason()]
  def reasons_related_to_datasets do
    @reasons_rules
    |> Map.filter(fn
      {_, %{scope: :dataset}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @spec platform_wide_reasons :: [reason()]
  def platform_wide_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{scope: :platform}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @doc """
  iex> subscribable_reasons_related_to_datasets(:reuser) != subscribable_reasons_related_to_datasets(:producer)
  true
  """
  @spec subscribable_reasons_related_to_datasets(role()) :: [reason()]
  def subscribable_reasons_related_to_datasets(role) do
    MapSet.new(reasons_related_to_datasets())
    |> MapSet.intersection(MapSet.new(reasons_for_role(role)))
    |> MapSet.intersection(MapSet.new(subscribable_reasons()))
    |> MapSet.to_list()
  end

  @doc """
  iex> subscribable_platform_wide_reasons(:reuser) != subscribable_platform_wide_reasons(:producer)
  true
  iex> subscribable_platform_wide_reasons(:producer)
  [:daily_new_comments]
  iex> subscribable_platform_wide_reasons(:reuser)
  [:daily_new_comments, :datasets_switching_climate_resilience_bill, :new_dataset]
  """
  @spec subscribable_platform_wide_reasons(role()) :: [reason()]
  def subscribable_platform_wide_reasons(role) do
    platform_wide_reasons()
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(reasons_for_role(role)))
    |> MapSet.intersection(MapSet.new(subscribable_reasons()))
    |> MapSet.to_list()
  end

  @doc """
  iex> shown_subscribable_platform_wide_reasons(:reuser)
  [:daily_new_comments, :new_dataset]
  """
  @spec shown_subscribable_platform_wide_reasons(role()) :: [reason()]
  def shown_subscribable_platform_wide_reasons(role) do
    subscribable_platform_wide_reasons(role) -- hidden_reasons_for_role(role)
  end

  @doc """
  The following configuration map for translations can’t be merged in the global configuration map
  because module attributes are compiled and not evaluated, which would freeze the translation to default locale.
  """
  @spec reason_to_str(reason() | binary()) :: binary()
  def reason_to_str(reason) when is_binary(reason), do: reason |> String.to_existing_atom() |> reason_to_str()

  def reason_to_str(reason) do
    Map.fetch!(
      %{
        expiration: dgettext("notification_subscription", "expiration"),
        dataset_with_error: dgettext("notification_subscription", "dataset_with_error"),
        resource_unavailable: dgettext("notification_subscription", "resource_unavailable"),
        dataset_now_on_nap: dgettext("notification_subscription", "dataset_now_on_nap"),
        new_dataset: dgettext("notification_subscription", "new_dataset"),
        datasets_switching_climate_resilience_bill:
          dgettext("notification_subscription", "datasets_switching_climate_resilience_bill"),
        daily_new_comments: dgettext("notification_subscription", "daily_new_comments"),
        resources_changed: dgettext("notification_subscription", "resources_changed"),
        periodic_reminder_producers: dgettext("notification_subscription", "periodic_reminder_producers"),
        promote_producer_space: dgettext("notification_subscription", "promote_producer_space"),
        promote_reuser_space: dgettext("notification_subscription", "promote_reuser_space"),
        warn_user_inactivity: dgettext("notification_subscription", "warn_user_inactivity")
      },
      reason
    )
  end
end
