# Changelog

This file lists the changes that affect deployments of the AWS and Azure modules. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow [Semantic Versioning](https://semver.org/). Before version 1.0, a minor release can include breaking changes.

Each entry names the platform it affects. A breaking entry says what to do before you apply the new version.

## Unreleased

### Breaking

- **AWS:** the `lambda_runtime` variable accepts only `python3.11` or later. If you set an older runtime, change it before you apply.
- **AWS:** the configuration requires AWS provider 5.76 or later, below 6.0. Run `tofu init -upgrade` if your lock file pins an older provider.
- **AWS:** the Lambda function writes JSON logs. Update CloudWatch metric filters, subscription filters, or log queries that match the old text output.
- **AWS:** the webhook returns the status codes of the [manual setup guide](https://docs.scalr.io/docs/serverless-aws-fargate): `202` with the `taskArn` when ECS accepts the launch, `400` without an `Idempotency-Key` header, and `502` when the ECS request or the launch fails. A request without the header no longer starts a task.
- **AWS and Azure:** agent containers write JSON logs (`SCALR_AGENT_LOG_FORMAT=json`). Update log queries that match the old text output.

### Added

- **AWS:** the Lambda function passes the SHA-256 hash of the webhook `Idempotency-Key` header to ECS `RunTask` as `clientToken`. Webhook retries for the same agent task no longer start extra Fargate tasks.
- **AWS and Azure:** the `agent_environment` variable sets extra environment variables, such as `SCALR_AGENT_*` options, on the agent container.
- **AWS and Azure:** the webhook endpoint sets the `SCALR_AGENT_DEDICATED_*` options from the `agent_environment` field of the webhook payload on the agent container. With `SCALR_AGENT_DEDICATED_TASK_ID`, the agent runs only the task it was started for and exits when that task is already taken, canceled, or finished. Agent versions without the option ignore it.
- **AWS and Azure:** the webhook response reports the launcher version in the `Scalr-Launcher-Version` header, starting with `0.1.0`, and the launcher type, the service that runs the launcher, in the `Scalr-Launcher-Type` header: `aws-lambda` on AWS and `azure-api-management` on Azure. Scalr shows both on the agent pool.
- **AWS:** the Lambda function sets `startedBy` on each Fargate task to the run ID and tags the task with the run, agent task, workspace, and environment IDs and the action. `aws ecs list-tasks --started-by <run-id>` finds the task of a run. The Lambda role gets `ecs:TagResource`, limited to tagging during `RunTask`.
- **AWS and Azure:** the `scalr_url` variable sets the Scalr URL the agent connects to. It defaults to `https://<account>.scalr.io`. Set it when Scalr runs at another host.

### Changed

- **AWS and Azure:** agent containers use `SCALR_AGENT_TOKEN`, `SCALR_AGENT_SINGLE`, and `SCALR_AGENT_DRIVER`. The agent deprecates the `SCALR_`-prefixed names and removes them in agent 2.0.0. `SCALR_URL` keeps its name because the agent reads only that name.
- **AWS:** the default `lambda_runtime` is `python3.13`.
- **AWS and Azure:** agent containers default to 4 vCPU and 8 GB (`ecs_limit_cpu = 4096` and `ecs_limit_memory = 8192` on AWS, `container_cpu = 4` and `container_memory_gb = 8` on Azure), up from 2 vCPU and 4 GB. This doubles the compute cost per run. Set the variables to keep the old size.
- **AWS:** the agent task no longer sets `SCALR_AGENT_TIMEOUT`. The agent has no such option, so the variable had no effect. `ecs_task_stop_timeout` still sets the ECS stop timeout.
- **AWS and Azure:** the agent cache uses one volume, mounted at `/scalr-agent-cache`. The apply deletes the unused `providers-cache` EFS access point on AWS and the `providers-cache` file share on Azure.
- **AWS and Azure:** agent containers no longer set `TF_PLUGIN_CACHE_DIR` and `TF_DATA_DIR`. The agent starts each run with its own environment, so these variables never reached OpenTofu or Terraform.

### Fixed

- **AWS:** `tofu apply` deploys changes to the Lambda function code. Before this fix, the function kept the code from its first deployment.
- **AWS:** a webhook returns `502` when ECS cannot launch the task. Before this fix, it returned `200` and Scalr did not retry.
- **AWS:** the ECS request uses one attempt with a 5-second read timeout, so the webhook responds within Scalr's 15-second timeout.
- **AWS:** the Lambda function no longer logs the request headers, which included the API key.
- **AWS and Azure:** the agent keeps OpenTofu and Terraform binaries, providers, and modules on the persistent cache (`SCALR_AGENT_CACHE_DIR=/scalr-agent-cache`). Before this fix, the agent cached them on the container disk, and every run downloaded them again.
- **AWS:** a change to the API Gateway IP allowlist, including `allow_all_ingress`, redeploys the API stage. Before this fix, the stage kept the old resource policy until another change redeployed it. With `allow_all_ingress = true`, the API now keeps a resource policy that allows every IP address, instead of having none.

### Documentation

- **Azure:** the README states that the module does not deduplicate webhook retries. The Container Apps Job start API has no idempotency key, so a retry can start an extra agent that finds no run and exits.
- **AWS and Azure:** the READMEs give a minimal install: clone a release tag, export the Scalr settings, and run `tofu apply`. `SCALR_ACCOUNT_ID` is listed with the other Scalr provider settings.
- The README no longer describes building a custom image with providers in `/terraform-cache/`. The cache volume hides that directory, and the agent uses its own cache layout.
