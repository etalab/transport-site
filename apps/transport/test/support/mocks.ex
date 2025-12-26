Mox.defmock(Transport.ExAWS.Mock, for: ExAws.Behaviour)
Mox.defmock(Shared.Validation.Validator.Mock, for: Shared.Validation.Validator)
Mox.defmock(Transport.Rambo.Mock, for: Transport.RamboLauncher)
Mox.defmock(Transport.GBFSMetadata.Mock, for: Transport.GBFSMetadata.Wrapper)
Mox.defmock(Transport.AvailabilityChecker.Mock, for: Transport.AvailabilityChecker.Wrapper)
Mox.defmock(Transport.Validators.JSONSchema.Mock, for: Transport.Validators.JSONSchema.Wrapper)
Mox.defmock(Transport.Validators.TableSchema.Mock, for: Transport.Validators.TableSchema.Wrapper)
Mox.defmock(Transport.History.Fetcher.Mock, for: Transport.History.Fetcher)
Mox.defmock(Hasher.Mock, for: Hasher.Wrapper)
Mox.defmock(Transport.ValidatorsSelection.Mock, for: Transport.ValidatorsSelection)
Mox.defmock(Transport.SIRIQueryGenerator.Mock, for: Transport.SIRIQueryGenerator.Behaviour)
Mox.defmock(Transport.Unzip.S3.Mock, for: Transport.Unzip.S3.Behaviour)
Mox.defmock(Transport.EnRouteChouetteValidClient.Mock, for: Transport.EnRouteChouetteValidClient.Wrapper)

Mox.defmock(Transport.Validators.MobilityDataGTFSValidatorClient.Mock,
  for: Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper
)

Mox.defmock(Unlock.BatchMetrics.Mock, for: Unlock.EventIncrementer)
Mox.defmock(Transport.Schemas.Mock, for: Transport.Schemas.Wrapper)

Mox.defmock(Unlock.Config.Fetcher.Mock, for: Unlock.Config.Fetcher)
Mox.defmock(Unlock.HTTP.Client.Mock, for: Unlock.HTTP.Client)
