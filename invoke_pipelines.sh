#!/bin/sh

if [ -f pipelines_to_invoke.txt ]; then
  while read -r pipeline_name; do
    echo "Invoking ${pipeline_name}"
    PIPELINE_ID=$(jq -r --arg PIPELINE_NAME "${pipeline_name}" '.[] | select(.metadata.name == $PIPELINE_NAME) | .metadata.id' pipelines.json)
    codefresh run "${PIPELINE_ID}"
  done < pipelines_to_invoke.txt
fi
