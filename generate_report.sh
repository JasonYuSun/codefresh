#!/bin/sh

CODEFRESH_API_KEY="YOUR_CODEFRESH_API_KEY"

echo "# Failed Pipelines" > failed_pipelines_report.md
echo "" >> failed_pipelines_report.md

jq -c '.[]' pipelines.json | while read -r pipeline; do
  PIPELINE_ID=$(echo "${pipeline}" | jq -r '.metadata.id')
  PIPELINE_NAME=$(echo "${pipeline}" | jq -r '.metadata.name')

  LAST_BUILD=$(curl -s -H "Authorization: ${CODEFRESH_API_KEY}" "https://g.codefresh.io/api/builds?pipelineId=${PIPELINE_ID}&limit=1" | jq '.[0]')
  if [ "${LAST_BUILD}" != "null" ]; then
    LAST_BUILD_STATUS=$(echo "${LAST_BUILD}" | jq -r '.status')

    if [ "${LAST_BUILD_STATUS}" != "success" ]; then
      echo "## ${PIPELINE_NAME}" >> failed_pipelines_report.md
      echo "" >> failed_pipelines_report.md
      echo "- Last build status: ${LAST_BUILD_STATUS}" >> failed_pipelines_report.md
      echo "" >> failed_pipelines_report.md
    fi
  fi
done
