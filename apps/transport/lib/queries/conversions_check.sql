with conversion_types as (
	select distinct convert_from, convert_to from data_conversion
), history as (
	select * from resource_history
), base as (
    select * from history cross join conversion_types
), conversions as (
    select convert_from, convert_to, resource_history_uuid from data_conversion
)

select 
  id as rh_id,
  datagouv_id as r_datagouv_id,
  payload ->> 'uuid' as rh_uuid,
  inserted_at as rh_inserted_at,
  base.convert_from,
  base.convert_to,
  case when resource_history_uuid IS NULL THEN false else true end as conversion_recorded
from base
left join conversions on
    base.payload ->> 'uuid' = conversions.resource_history_uuid::text AND
    base.convert_from = conversions.convert_from AND
    base.convert_to = conversions.convert_to
