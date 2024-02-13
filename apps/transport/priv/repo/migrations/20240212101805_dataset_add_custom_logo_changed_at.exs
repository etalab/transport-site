defmodule DB.Repo.Migrations.DatasetAddCustomLogoChangedAt do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:custom_logo_changed_at, :utc_datetime_usec, null: true)
    end

    execute(
      """
        update dataset set custom_logo_changed_at = t.custom_logo_changed_at::timestamp
        from (
          select '5d6eaffc8b4c417cdc452ac3' datagouv_id, '2024-02-09 08:17:00' custom_logo_changed_at union
          select '60a50049fb874038a79867df' datagouv_id, '2024-02-07 13:16:00' custom_logo_changed_at union
          select '60e324396e9514171898339c' datagouv_id, '2024-02-07 13:16:00' custom_logo_changed_at union
          select '60e32505bdb603a010708d6c' datagouv_id, '2024-02-07 13:16:00' custom_logo_changed_at union
          select '60febcaaf6d99c72ca482ac4' datagouv_id, '2024-02-07 13:16:00' custom_logo_changed_at union
          select '625438b890bf88454b283a55' datagouv_id, '2024-02-09 08:17:00' custom_logo_changed_at union
          select '632a56a687192cc1b58c0d3a' datagouv_id, '2024-02-09 13:44:00' custom_logo_changed_at union
          select '632a56a68a907ff3d4eacfa4' datagouv_id, '2024-01-24 10:02:00' custom_logo_changed_at union
          select '632a56a6a0eb7f886aeacfa4' datagouv_id, '2024-02-09 14:07:00' custom_logo_changed_at union
          select '632a56a6a0eb7f886aeacfa5' datagouv_id, '2024-02-09 14:07:00' custom_logo_changed_at union
          select '632a56a74916728dc7eacfa6' datagouv_id, '2024-02-09 14:07:00' custom_logo_changed_at union
          select '632a56a7a0eb7f886aeacfa7' datagouv_id, '2024-02-09 14:09:00' custom_logo_changed_at union
          select '638a2bd69c7bba6c44d36efa' datagouv_id, '2024-02-07 13:15:00' custom_logo_changed_at union
          select '63b4c3d106d317f5caa80dc9' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d106d317f5caa80dca' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d200fbf8e5ed9dde9a' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d200fbf8e5ed9dde9b' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d206d317f5caa80dcd' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d206d317f5caa80dce' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d22989785f7e9dde9a' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d22989785f7e9dde9d' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d255130e7bb19dde9a' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d255130e7bb19dde9b' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d255130e7bb19dde9c' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d25a09dd67fc9dde9d' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d25c38a3ee979dde9b' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d25c38a3ee979dde9c' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d25e8da006139dde9a' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d25e8da006139dde9b' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d274694a83b49dde9c' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d2998fd84635a80dca' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d2998fd84635a80dcb' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d2d7857ab0c49dde9b' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d2d7857ab0c49dde9c' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d300fbf8e5ed9dde9d' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d300fbf8e5ed9dde9e' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d32989785f7e9dde9e' datagouv_id, '2024-01-29 16:07:00' custom_logo_changed_at union
          select '63b4c3d355130e7bb19dde9d' datagouv_id, '2024-01-29 16:08:00' custom_logo_changed_at union
          select '63b4c3d35a09dd67fc9dde9e' datagouv_id, '2024-01-29 16:08:00' custom_logo_changed_at union
          select '63b4c3d35e8da006139dde9d' datagouv_id, '2024-01-29 16:08:00' custom_logo_changed_at union
          select '64d0f399b37ace5777f8b27a' datagouv_id, '2024-02-07 13:16:00' custom_logo_changed_at union
          select '651d2ece3af956b8dd0d7648' datagouv_id, '2024-02-09 08:22:00' custom_logo_changed_at union
          select '658626a8d94ad9e953c71b48' datagouv_id, '2024-02-07 13:59:00' custom_logo_changed_at union
          select '658626a9e96365230bac182c' datagouv_id, '2024-02-07 14:10:00' custom_logo_changed_at union
          select '658626a9e96365230bac182d' datagouv_id, '2024-02-07 13:58:00' custom_logo_changed_at
        ) t where dataset.datagouv_id = t.datagouv_id;
      """,
      ""
    )
  end
end
