Logger.configure(level: :info)

import Ecto.Query

defmodule Report do
  def report(data_import_batch_id) do
    DB.Repo.get_by(DB.DataImportBatch, id: data_import_batch_id).summary["result"]
  end
end

batch_id =
  unless System.get_env("SKIP_IMPORT") == "1" do
    %{data_import_batch_id: batch_id} = Transport.Jobs.GTFSImportStopsJob.refresh_all()
    batch_id
  else
    %{id: batch_id} = DB.Repo.one(from(dib in DB.DataImportBatch, order_by: [desc: dib.id], limit: 1))
    batch_id
  end

Report.report(batch_id)
|> IO.inspect(IEx.inspect_opts())
