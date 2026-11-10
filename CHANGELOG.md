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
- **AWS:** the Lambda function sets the agent options from the `agent_environment` field of the webhook payload on the agent container, limited to `SCALR_AGENT_*` options other than `SCALR_AGENT_TOKEN` and `SCALR_AGENT_SINGLE`. Scalr passes `SCALR_AGENT_TASK_ID`, so the agent claims only the task it was started for and exits when that task is already taken, canceled, or finished. Agents without the option ignore it.
- **AWS:** the webhook response reports the launcher version in the `Scalr-Launcher-Version` header, starting with `0.1.0`. Scalr shows it on the agent pool.

### Changed

- **AWS and Azure:** agent containers use `SCALR_AGENT_TOKEN`, `SCALR_AGENT_SINGLE`, and `SCALR_AGENT_DRIVER`. The agent deprecates the `SCALR_`-prefixed names and removes them in agent 2.0.0. `SCALR_URL` keeps its name because the agent reads only that name.
- **AWS:** the default `lambda_runtime` is `python3.13`.
- **AWS and Azure:** agent containers default to 4 vCPU and 8 GB (`ecs_limit_cpu = 4096` and `ecs_limit_memory = 8192` on AWS, `container_cpu = 4` and `container_memory_gb = 8` on Azure), up from 2 vCPU and 4 GB. This doubles the compute cost per run. Set the variables to keep the old size.
- **AWS:** the agent task no longer sets `SCALR_AGENT_TIMEOUT`. The agent has no such option, so the variable had no effect. `ecs_task_stop_timeout` still sets the ECS stop timeout.

### Fixed

- **AWS:** `tofu apply` deploys changes to the Lambda function code. Before this fix, the function kept the code from its first deployment.
- **AWS:** a webhook returns `502` when ECS cannot launch the task. Before this fix, it returned `200` and Scalr did not retry.
- **AWS:** the ECS request uses one attempt with a 5-second read timeout, so the webhook responds within Scalr's 15-second timeout.
- **AWS:** the Lambda function no longer logs the request headers, which included the API key.

### Documentation

- **Azure:** the README states that the module does not deduplicate webhook retries. The Container Apps Job start API has no idempotency key, so a retry can start an extra agent that finds no run and exits.
