#!/bin/sh

CODEFRESH_API_KEY="YOUR_CODEFRESH_API_KEY"

if [ -f pipelines_to_invoke.txt ]; then
  while read -r pipeline_name; do
    echo "Invoking ${pipeline_name}"
    PIPELINE_ID=$(jq -r --arg PIPELINE_NAME "${pipeline_name}" '.[] | select(.metadata.name == $PIPELINE_NAME) | .metadata.id' pipelines.json)
    curl -s -X POST -H "Authorization: ${CODEFRESH_API_KEY}" "https://g.codefresh.io/api/builds?pipelineId=${PIPELINE_ID}"
  done < pipelines_to_invoke.txt
fi
