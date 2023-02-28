# Insert `DB.NotificationSubscription` rows in the database using a notifications' config in YAML.
# It looks up for the associated dataset and contact, which must exist.
# Run with `mix run scripts/contacts/insert_notification_subscriptions.exs`

yaml_config_filepath = "/tmp/config.yml"

defmodule Converter do
  def convert({"expiration", data}) do
    Enum.flat_map(data, fn {slug, %{"emails" => emails}} ->
      Enum.map(emails, fn email -> ["expiration", slug, String.downcase(email)] end)
    end)
  end

  def convert({reason, emails}) do
    Enum.map(emails, fn email -> [reason, nil, String.downcase(email)] end)
  end
end

yaml_config_filepath
|> File.read!()
|> YamlElixir.read_from_string!()
|> Enum.flat_map(&Converter.convert/1)
|> Enum.map(fn [reason, dataset_slug, email] ->
  dataset_id =
    case dataset_slug do
      nil -> nil
      slug when is_binary(slug) -> DB.Repo.get_by!(DB.Dataset, slug: slug).id
    end

  contact_id = DB.Repo.get_by!(DB.Contact, email_hash: email).id

  DB.NotificationSubscription.insert!(%{
    contact_id: contact_id,
    dataset_id: dataset_id,
    source: :admin,
    reason: reason
  })
end)
