#!/bin/sh

CODEFRESH_API_KEY="YOUR_CODEFRESH_API_KEY"
TIME_24_HOURS_AGO=$(date -u -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

jq -c '.[] | select(.spec.runtime.variables[]? | select(.key == "AUTO_APPROVE" and .value == "true"))' pipelines.json | while read -r pipeline; do
  PIPELINE_ID=$(echo "${pipeline}" | jq -r '.metadata.id')
  PIPELINE_NAME=$(echo "${pipeline}" | jq -r '.metadata.name')

  LAST_SUCCESS_BUILD=$(curl -s -H "Authorization: ${CODEFRESH_API_KEY}" "https://g.codefresh.io/api/builds?pipelineId=${PIPELINE_ID}&status=success&limit=1" | jq '.[0]')
  if [ "${LAST_SUCCESS_BUILD}" != "null" ]; then
    LAST_SUCCESS_BUILD_TIME=$(echo "${LAST_SUCCESS_BUILD}" | jq -r '.finished')

    if [ "$(date -u -d "${LAST_SUCCESS_BUILD_TIME}" +%s)" -lt "$(date -u -d "${TIME_24_HOURS_AGO}" +%s)" ]; then
      echo "${PIPELINE_NAME} has not run successfully in the last 24 hours."
      echo "${PIPELINE_NAME}" >> pipelines_to_invoke.txt
    fi
  else
    echo "${PIPELINE_NAME} has never run successfully."
    echo "${PIPELINE_NAME}" >> pipelines_to_invoke.txt
  fi
done
