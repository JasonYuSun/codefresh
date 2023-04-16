### Step 1: Waiting for scheduled destruction.
The error might resolve itself once the scheduled destruction time passes. During each pipeline build, Terraform updates resources based on the codebase and state file. It tries to destroy the CryptoKeyVersion, as it expects the state to be "DESTROYED." Once the state changes from 'DESTROY_SCHEDULED' to 'DESTROYED,' Terraform should stop attempting deletion and the error should vanish. The team decided to rerun the pipeline after a long weekend to test this hypothesis.

The rerun pipelines failed with a different error message:
```
googleapi: Error 400: The request cannot be fulfilled. Resource projects/anz-x-fabric-p-641432/locations/australia-southeast1/keyRings/fabric-ges-key-ring-preprod-k/cryptoKeys/storage-crypto-key-fabric-profile-picture-preprod-k-293738/cryptoKeyVersions/1 has value DESTROVED in field crypto_key_version.state.
```

The error message implies that cryptoKeyVersions doesn't exist in Terraform's state file. Terraform attempts to destroy it because other resources' state is different from the desired state, which should be related to destroying the GCS bucket.

### Step 2: Investigate the connection between removing a GCS bucket and destroying a CryptoKeyVersion.

The next step involves understanding the relationship between removing a GCS bucket and destroying a CryptoKeyVersion. Upon examination, the codebase shows that when a new GCS bucket is created, a corresponding CryptoKey is generated for data encryption. If the bucket is removed, Terraform should destroy the associated CryptoKey. According to Terraform's documentation, CryptoKeys cannot be deleted from GCP; instead, their destruction is achieved through a series of actions, including destroying the CryptoKeyVersion. The sequence of events in the pipeline rerun was as follows:

1. A user merged a PR that removed the 'fabric-profile-picture' GCS bucket from the codebase.
2. The removal of the GCS bucket altered the desired state of the corresponding CryptoKey, prompting Terraform to plan its destruction.
3. Terraform attempted to destroy the CryptoKey by destroying the CryptoKeyVersion.
4. The CryptoKeyVersion's state had already been set to 'DESTROYED', so GCP could not fulfill Terraform's request.
5. Terraform reported an error message, causing the Do Apply step to fail.

The rerun pipeline failure suggests a Terraform bug in which the decision to destroy a CryptoKeyVersion is based on the target CryptoKey's state rather than the CryptoKeyVersion's state. If a CryptoKeyVersion has already been manually destroyed and its state is 'DESTROYED', Terraform will report an error and fail to apply changes. Notably, Terraform fixed this bug six months ago, but an older version is still being used, leaving the bug present. One outstanding question remains: Why did the error message indicate that the CryptoKeyVersion's state was 'DESTROY_SCHEDULED' when the user who reported the issue ran the pipeline?

### Step 3: Identify the cause of the CryptoKeyVersion's state being set to DESTROY_SCHEDULED

To determine why the CryptoKeyVersion's state was set to 'DESTROY_SCHEDULED', it is essential to understand when this state change occurs. According to GCP's official documentation, when a destruction request is submitted, the key version's state transitions to Scheduled for Destruction. The key material is not immediately destroyed; instead, it remains scheduled for destruction for a default period of 24 hours or a specified duration, after which it is automatically destroyed. This safety fallback cannot be overridden. Therefore, GCP must have received and executed a request to destroy the CryptoKeyVersion within 24 hours before the user encountered the error. 

Assuming no one manually destroyed the CryptoKeyVersion mentioned in the error message, a partial apply may have occurred within 24 hours before the user saw the error. In this scenario, Terraform could have been terminated while destroying the CryptoKey, leaving the CryptoKeyVersion destroyed. This hypothesis can be verified by locating the corresponding pipeline.

### Step 4: Search for the pipeline where the partial apply occurred

An anomaly was discovered when the user initially experienced a Do Apply failure due to excessively long pubsub_crypto_key names. This pipeline ran for nearly 40 minutes, significantly longer than the typical duration of less than 10 minutes. Another error code was identified in the pipeline's Do Apply log:

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
The preprod-k environment's pipeline requires user approval to execute the 'Do Apply' step. If a user merges code changes related to preprod-k but does not approve the plan or revert the code change, these changes will be applied when the next user approves the generated plan and executes the 'Do Apply' step. Many users may be unaware of the need to approve changes for this non-production environment, which can result in a pipeline build with 35 resources to add and 10 resources to destroy. This accumulation of changes leads to the RATE_LIMIT_EXCEEDED error and Terraform's partial apply.


I'm rewriting the fifth step, please help me reorganise the following sentence, make them better structured, more fluent, logical and easier to follow: 

### Step 5: Resolve the issue by manually completing the CryptoKey destruction process

The issue can be resolved by manually finishing the CryptoKey destruction process, which consists of three steps:

1. Ensure all CryptoKeyVersions are in the 'DESTROYED' state.
2. Disable automatic rotation of the CryptoKey.
3. Remove the CryptoKey from the Terraform state file.

The first two steps can be completed through the GCP console, while updating the state files must be done using a pipeline due to access control. The Break Glass pipeline is suitable for this situation because its workflow is defined by Inline YAML, making it easy to modify. Follow these steps to use the Break Glass pipeline to update the state file:

1. Preparation
   - Update the pipeline variables to match the preprod-k environment.
   - Retain the steps 'validate_input', 'main_clone', 'unlock tf_state', and 'generate_plan'; comment out the rest.
   - Clean up any residual code left by other users in the generate plan step and ensure it's commented out.
   - Locate the full name of the CryptoKey in the state file using the Terraform plan generated by previous pipeline builds.
   - Add the command to remove the CryptoKey from the Terraform state file to the 'generate_plan' step.
2. Save the changes and click "run".
3. Review the plan generated by the Break Glass pipeline. If the plan doesn't include destroying the CryptoKey, it has been successfully removed from the state file.

Once the CryptoKey is removed, rerun the most recent pipeline in the preprod-k environment, and the pipeline should build successfully.
