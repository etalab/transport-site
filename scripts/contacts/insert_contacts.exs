# Insert `DB.Contact` rows from a CSV file created by our team.
# Sample content:
# ```
# email,first_name,last_name,job_title,organization,phone_number
# foo.bar@example.fr,Foo,Bar,Boss,Loire Atlantique,
# ```
# See https://mattermost.incubateur.net/betagouv/pl/io33ern89traxkhmac5x1ue1ho
# Run with `mix run scripts/contacts/insert_contacts.exs`
csv_config_filepath = "/tmp/contacts.csv"

csv_config_filepath
|> File.stream!()
|> CSV.decode!(headers: true)
|> Enum.to_list()
|> Enum.each(fn %{} = data ->
  {_, data} =
    Map.get_and_update(data, "organization", fn current_value ->
      new_value =
        case current_value do
          "" -> "?"
          other -> other
        end

      {current_value, new_value}
    end)

  DB.Contact.insert!(data)
end)
