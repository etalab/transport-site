commands = [
  {"CheckStatus", "--target distribus --request check_status"},
  {"StopPointsDiscovery", "--target distribus --request stop_points_discovery"},
  {"LinesDiscovery", "--target distribus --request lines_discovery"},
  {"GetEstimatedTimetable",
   "--target distribus --request get_estimated_timetable --line-refs SAE_HANOVER:Line::04:LOC"},
  {"GetStopMonitoring",
   "--target distribus --request get_stop_monitoring --stop-ref SAE_HANOVER:StopPoint:BP:STA1A2:LOC"},
  {"GetGeneralMessage", "--target distribus --request get_general_message"}
]

for {title, c} <- commands do
  cmd = "elixir scripts/siri/siri_check.exs #{c} --dump-response | xmllint --format -"
  {output, 0} = System.shell(cmd)

  IO.puts("\n## #{title}")
  IO.puts("")
  IO.puts("`#{cmd}`")
  IO.puts("")
  IO.puts("")
  IO.puts("<details>")
  IO.puts("<summary>Response</summary>\n\n")
  IO.puts("```xml")
  IO.puts(output)
  IO.puts("```\n")
  IO.puts("</details>\n")
end
