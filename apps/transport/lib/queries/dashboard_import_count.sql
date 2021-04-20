/*
  Return the "count" of logs_import for each dataset and each day of a recent date range.

  NOTE: If we need to parameterize the date range, but still work with a raw SQL like here
  (easier to test with SQL tooling, without having to rewrite into Ecto SQL), we can have
  a look at https://hexdocs.pm/ayesql/AyeSQL.html.

*/

SELECT
	dataset_day.dataset_id, day, COALESCE(count, 0) as count
FROM (
	SELECT
		d.id AS dataset_id,
		day::date
	FROM
		generate_series(current_date - interval '30 day', current_date, '1 day') AS day,
		dataset d
	ORDER BY
		d.id ASC,
		day ASC) dataset_day
	LEFT JOIN (
		SELECT
			dataset_id,
			timestamp::date AS date,
			count(*) AS count
		FROM
			logs_import
		GROUP BY
			dataset_id,
			date) counts ON dataset_day.dataset_id = counts.dataset_id
	AND dataset_day.day = counts.date
