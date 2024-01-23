# Run script:
# `elixir scripts/custom_logo.exs /tmp/logo.jpg f0700f5f9954`
Mix.install([{:image, "~> 0.37"}])

require Logger

cellar_base_url = "http://transport-data-gouv-fr-logos-prod.cellar-c2.services.clever-cloud.com/"

{[], [src_path, datagouv_id]} = OptionParser.parse!(System.argv(), strict: [src_path: :string, datagouv_id: :string])

extension = src_path |> Path.extname() |> String.downcase()

logo_filename = "#{datagouv_id}#{extension}"
full_logo_filename = "#{datagouv_id}_full#{extension}"
logo_path = "/tmp/#{logo_filename}"
full_logo_path = "/tmp/#{full_logo_filename}"

src_path
|> Image.thumbnail!(100)
|> Image.embed!(100, 100, background_color: :white)
|> Image.write!(logo_path)

src_path
|> Image.thumbnail!(500)
|> Image.write!(full_logo_path)

Logger.info("Logos have been generated to:\n- #{logo_path}\n- #{full_logo_path}")

commands =
  [logo_path, full_logo_path]
  |> Enum.map_join("\n", fn path ->
    "s3cmd put --acl-public --add-header='Cache-Control: public, max-age=604800' #{path} s3://transport-data-gouv-fr-logos-prod/"
  end)

Logger.info("Run the following commands to upload files.\n#{commands}")

Logger.info(
  "Query:\nUPDATE dataset SET custom_logo = '#{cellar_base_url}#{logo_filename}', custom_full_logo = '#{cellar_base_url}#{full_logo_filename}' WHERE datagouv_id = '#{datagouv_id}';"
)
