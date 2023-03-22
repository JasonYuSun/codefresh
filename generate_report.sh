#!/bin/sh

if [ -f pipelines_to_invoke.txt ]; then
  echo "# Failed Pipelines Report" > failed_pipelines_report.md
  echo "The following pipelines have not run successfully in the last 24 hours:" >> failed_pipelines_report.md
  echo "" >> failed_pipelines_report.md

  while read -r pipeline_name; do
    echo "- ${pipeline_name}" >> failed_pipelines_report.md
  done < pipelines_to_invoke.txt
else
  echo "All pipelines have run successfully in the last 24 hours."
fi
