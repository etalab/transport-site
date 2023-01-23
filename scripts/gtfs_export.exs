require Logger

# TODO: use a scalable pattern (e.g. chunked by data import would work), since it will time out here.
# Keeping for reference during development.
Logger.info("Loading data import ids...")

data_import_ids = Transport.GTFSExportStops.data_import_ids()

Logger.info("Loading stops...")

export = Transport.GTFSExportStops.export_stops_report(data_import_ids)

Logger.info("Done...")
