# Resolving Pipeline Errors Due to Google API and Terraform Issues

## Introduction

This document provides a step-by-step guide on resolving pipeline errors caused by Google API error 400 and Terraform issues when adding new GCS buckets and PubSub topics in multiple environments.

## Table of Contents

- [Resolving Pipeline Errors Due to Google API and Terraform Issues](#resolving-pipeline-errors-due-to-google-api-and-terraform-issues)
  - [Introduction](#introduction)
  - [Table of Contents](#table-of-contents)
  - [Issue Summary](#issue-summary)
  - [Steps to Check and Resolve the Issue](#steps-to-check-and-resolve-the-issue)
    - [Context and Background Knowledge](#context-and-background-knowledge)
    - [Checking and Resolving the Issue](#checking-and-resolving-the-issue)

## Issue Summary

A user encountered issues when attempting to add new GCS buckets and PubSub topics in intpnv, pnv, preprod-k, preprod, sit-n, sit, st via Terraform. The pipeline builds failed at the 'Do Apply' step, presenting two different error messages:

1. In pnv and sit environments, the error message displayed was:
```
Error: Error trying to delete bucket fabric-profile-picture-py containing objects without 'force_destroy' set to true.
```


2. In other environments, the error message displayed was:

```
Error: Error creating CryptoKey: googleapi: Error 400: crypto_key_id: 'pubsub-cryto-key-txns-historical-moneytracker-regs-preprod-K-15c547' does not match pattern '.*([a-zA-Z0-9-_]{1,63})'.
```

The first error occurred because a previous user's merged PR attempted to remove GCS buckets 'fabric-profile-picture' located in intpn, pnv, preprod-k, preprod-n, preprod, sit-k, sit-n, sit, st without setting the force_destroy flag to true. The buckets in sit and pny were not empty, causing Terraform to fail when deleting the buckets in the two environments. After manually deleting the two buckets and rerunning the pipeline, the first error was resolved.

The second error occurred due to the pubsub_crypto_key name assigned by the reporting user being too long. Renaming the resources resolved the second issue, and the pubsub topics and GCS buckets were successfully created in intpnv, pnv, preprod, sit-n, sit, st, except for preprod-k.

The pipeline in preprod-k failed with the following error message:
```
Error: googleapi: Error 400: The request cannot be fulfilled. Resource projects/anz-x-fabric-p-641432/Locations/australia-southeast1/keyRings/fabric-gcs-key-ring-preprod-k/cryptoKeys/storage-crypto-key-fabric-profile-picture-preprod-K-293738/cryptoKeyVersions/1 has value DESTROY_SCHEDULED in field crypto_key_version.state.
```

## Steps to Check and Resolve the Issue

### Context and Background Knowledge

**The pipeline in the preprod-k environment requires user approval for executing the 'Do Apply' step**. If a user merges code changes related to preprod-k but does not approve the plan or revert the code change, the changes are applied when the next user approves the generated plan and executes the 'Do Apply' step.

### Checking and Resolving the Issue

The error might resolve itself once the scheduled destruction time passes. During each pipeline build, Terraform updates resources based on the codebase and state file. It tries to destroy the CryptoKeyVersion, as it expects the state to be "DESTROYED." Once the state changes from 'DESTROY_SCHEDULED' to 'DESTROYED,' Terraform should stop attempting deletion and the error should vanish. The team decided to rerun the pipeline after a long weekend to test this hypothesis.

The rerun pipelines failed with a different error message:
```
googleapi: Error 400: The request cannot be fulfilled. Resource projects/anz-x-fabric-p-641432/locations/australia-southeast1/keyRings/fabric-ges-key-ring-preprod-k/cryptoKeys/storage-crypto-key-fabric-profile-picture-preprod-k-293738/cryptoKeyVersions/1 has value DESTROVED in field crypto_key_version.state.
```

The error message implies that cryptoKeyVersions doesn't exist in Terraform's state file. Terraform attempts to destroy it because other resources' state is different from the desired state, which should be related to destroying the GCS bucket.

Based on the current information, three questions can be initiated:

1. What's the connection between removing a GCS bucket and destroying a CryptoKeyVersion?
2. Why was the CryptoKeyVersion's state set to DESTROY_SCHEDULED when the user who raised the issue applied the change?
3. Why has this error only occurred in the preprod-k environment?

The first question was answered by examining relevant code and Terraform's official documentation. The codebase reveals that when a new GCS bucket is created, a corresponding CryptoKey is also generated for data encryption. If the bucket is removed, the associated CryptoKey should also be destroyed by Terraform. According to Terraform's documentation, destroying a CryptoKey involves a series of actions, including destroying the CryptoKeyVersion.

To answer the second question, it's important to understand when a CryptoKeyVersion's state becomes 'DESTROY_SCHEDULED.' GCP's official documentation explains that when a destruction request is submitted, the key version's state changes to Scheduled for Destruction. The key material isn't immediately destroyed; instead, it remains scheduled for destruction for a default period of 24 hours or a configured duration, after which it is automatically destroyed. This safety fallback can't be overridden. Thus, within the 24 hours before the user encountered the error, GCP received a request to destroy the CryptoKeyVersion and executed it.

These answers suggest a Terraform bug, where it decides whether to destroy a CryptoKeyVersion based on the target CryptoKey's state rather than the CryptoKeyVersion's state. This issue results in errors if any CryptoKeyVersion's state is DESTROYED, even if it's already been destroyed manually. Terraform fixed this bug six months ago. Additionally, if no one manually destroyed the CryptoKeyVersion in the error message, a partial apply might have occurred within 24 hours before the user saw the error. Terraform could have been terminated while destroying the CryptoKey and had destroyed the CryptoKeyVersion. This hypothesis can be confirmed by finding the corresponding pipeline.

An anomaly was found when the user initially encountered a Do Apply failure due to overly long pubsub_crypto_key names; the pipeline ran for nearly 40 minutes, while it usually takes less than 10 minutes. Another error code was discovered in the pipeline's Do Apply log:
```
[2023-04-05T04:40:14.000Z]
Error: While cryptoKeyVersions were cleared, Terraform was unable to disable automatic rotation of key due to an error: googleapi: Error 429: Quota exceeded for quota metric Write requests and limit write requests per minute' of service cloudkms.googleapis.com' for consumer 'project_number: 240970868086.

Details:
{
  "type": "type.googleapis.com/google.rpc.ErrorInfo",
  "domain": "googleapis.com",
  "metadata": {
    "consumer": "projects/240970868086",
    "quota_limit": "WriteRequestsPerMinutePerProject",
    "quota_limit_value": "60",
    "quota_location": "global",
    "quota_metric": "cloudkms.googleapis.com/write_requests",
    "service": "cloudkms.googleapis.com"
  },
  "reason": "RATE_LIMIT_EXCEEDED",
  "@type": "type.googleapis.com/google.rpc.Help",
  "links": [
    {
      "description": "Request a higher quota limit.",
      "url": "https://cloud.google.com/docs/quota/requesting-higher-quota"
    }
  ]
}
, rateLimitExceeded.Please retry or manually disable automatic rotation to prevent creation of a new version of this key.   
```

This pipeline build has 35 resources to add and 10 resources to destroy. The pipeline in preprod-k doesn't apply changes without user approval, and many users may not realize they need to approve changes for this non-prod environment, which could lead to a large modification, resulting in the RATE_LIMIT_EXCEEDED error and Terraform's partial apply. This is why the error only appears in preprod-k.

[2023-04-05704:04:25.854Z) Plan: 35 to add, 0 to change, 10 to destroy.

## Solution

The issue can be resolved by manually completing the CryptoKey destruction process, which includes three steps:

1. Ensure all CryptoKeyVersions are in the 'DESTROYED' state.
2. Disable automatic rotation of the CryptoKey.
3. Remove the CryptoKey from the Terraform state file.

The first two steps can be done via the GCP console. Updating the state files requires using a pipeline due to access control. The Break Glass pipeline is designed for this scenario, as its workflow is defined by Inline YAML, which is easy to modify. The process of using the Break Glass pipeline to modify the state file is as follows:

1. Prepare
   - Update the pipeline variables to match those of preprod-k.
   - Retain the steps: 'validate_input', 'main_clone', 'unlock tf_state', and 'generate_plan'; comment out the rest.
   - Reorganize any residual code left by other users in the generate plan step and ensure it's commented out.
   - Find the full name of the CryptoKey in the state file from the Terraform plan generated by previous pipeline builds.
   - Add the command to remove the CryptoKey from the Terraform state file to the 'generate_plan' step.
2. Save changes and click "run".
3. Check the plan generated by the Break Glass pipeline. If the plan doesn't destroy the CryptoKey, it has been successfully removed from the state file.

After removing the CryptoKey, rerun the latest pipeline in preprod-k, and the pipeline should build successfully.

## Summary
The issue originated when a user attempted to add new GCS buckets and PubSub topics via Terraform, causing pipeline builds to fail in several environments. The failure in the 'Do Apply' step was due to two main errors: one related to GCS bucket deletion without the force_destroy flag set to true, and the other related to an overly long name for the pubsub_crypto_key.

After resolving these errors, a new issue emerged in the preprod-k environment with Terraform attempting to destroy a CryptoKeyVersion with a 'DESTROY_SCHEDULED' state. The root cause was traced back to Terraform's incorrect handling of CryptoKeyVersion destruction and a possible partial apply caused by a rate limit exceeded error.

To resolve this issue, the CryptoKey destruction process was manually completed using the Break Glass pipeline. This included ensuring all CryptoKeyVersions were in the 'DESTROYED' state, disabling automatic rotation of the CryptoKey, and removing the CryptoKey from the Terraform state file. After completing these steps, the pipeline in preprod-k built successfully.
