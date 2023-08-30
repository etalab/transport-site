# Scaleway bucket configurations

We use Scaleway for database backups replication.

This folder holds configuration for:
- bucket policies (permissions)
- bucket lifecycles (how long to keep uploaded files, when to delete temporary files)

## Scaleway documentation links

- [Using bucket policies](https://www.scaleway.com/en/docs/storage/object/api-cli/using-bucket-policies/)
- [Managing the lifecycle of objects](https://www.scaleway.com/en/docs/storage/object/api-cli/lifecycle-rules-api/)

[See the GitHub issue comment](https://github.com/etalab/transport-site/issues/1548#issuecomment-1083189225) explaining what has been implemented.

## Seeing / applying configuration

At the moment **these configuration are NOT automatically applied** through CI or something else. You'll need to run CLI commands.

Grab Scaleway credentials from our password manager solution first and [install the AWS CLI](https://www.scaleway.com/en/docs/storage/object/api-cli/object-storage-aws-cli/).

### CLI commands related to lifecycles
```
# See the lifecycle configuration
aws --endpoint-url "https://s3.fr-par.scw.cloud" --region fr-par s3api get-bucket-lifecycle-configuration --bucket transport-staging-backups
aws --endpoint-url "https://s3.fr-par.scw.cloud" --region fr-par s3api get-bucket-lifecycle-configuration --bucket transport-prod-backups
# Apply a lifecycle configuration to a bucket
aws --endpoint-url "https://s3.fr-par.scw.cloud" --region fr-par s3api put-bucket-lifecycle-configuration --lifecycle-configuration file:///Users/antoineaugusti/Documents/transport-site/docs/scaleway/bucket_lifecycle_configuration_production.json --bucket transport-prod-backups

### CLI commands related to bucket policies
```
# See a bucket policy configuration
aws --endpoint-url "https://s3.fr-par.scw.cloud" --region fr-par s3api get-bucket-policy --bucket transport-prod-backups 

# Apply a bucket policy configuration to a bucket
aws --endpoint-url "https://s3.fr-par.scw.cloud" --region fr-par s3api put-bucket-policy --bucket transport-prod-backups --policy file://docs/scaleway/bucket_policy_production.json
```
