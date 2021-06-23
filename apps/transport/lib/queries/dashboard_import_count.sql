/*
  Return :
  - the "count" of logs_import for each dataset and each day of a recent date range (import_counts)
  - the count of logs_import full success for each dataset and each day of a recent date range (success_counts)

  NOTE: If we need to parameterize the date range, but still work with a raw SQL like here
  (easier to test with SQL tooling, without having to rewrite into Ecto SQL), we can have
  a look at https://hexdocs.pm/ayesql/AyeSQL.html.

*/

with dates as (
select
	d.id as dataset_id,
	day::date
from
	generate_series(current_date - interval '30 day', current_date, '1 day') as day,
	dataset d),

import_counts as (
select
	dataset_id,
	timestamp::date as date,
	count(*) as count
from
	logs_import
group by
	dataset_id,
	date),

  success_counts as (
select
	dataset_id,
	timestamp::date as date,
	count(*) as count
from
	logs_import
  WHERE is_success = TRUE

group by
	dataset_id,
	date)

select
	dates.*,
	coalesce(import_counts.count, 0) as import_counts,
  coalesce(success_counts.count, 0) as success_counts
from
	dates
left join import_counts on
	dates.day = import_counts.date
	and dates.dataset_id = import_counts.dataset_id
left join success_counts on
	dates.day = success_counts.date
	and dates.dataset_id = success_counts.dataset_id;
