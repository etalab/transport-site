/*
  Return the "count" of logs_import for each dataset and each day of a recent date range.

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

counts as (
select
	dataset_id,
	timestamp::date as date,
	count(*) as count
from
	logs_import
group by
	dataset_id,
	date)

select
	dates.*,
	coalesce(counts.count, 0) as count
from
	dates
left join counts on
	dates.day = counts.date
	and dates.dataset_id = counts.dataset_id;
