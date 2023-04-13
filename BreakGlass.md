The error seems to be related to a prior code change that removed a GCS bucket. Terraform is having trouble destroying a CryptoKeyVersion because its state is 'destroy_scheduled'. It's likely that the error will disappear automatically once the scheduled destruction time arrives.

During each pipeline build, Terraform refreshes the state of resources in the state file and generates the desired states based on the codebase. Then, using the state file, it creates a plan to update the resources accordingly. Currently, Terraform is trying to destroy the CryptoKeyVersion because it believes its desired state, according to the plan, is 'destroyed'. Once the state changes from 'scheduled_destroy' to 'destroyed', Terraform should no longer attempt deletion, and the error should no longer appear. I decided to rerun the pipeline after a long weekend to see if this would resolve the issue.



