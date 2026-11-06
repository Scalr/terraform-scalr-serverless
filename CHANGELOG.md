# Changelog

This file lists the changes that affect deployments of the AWS and Azure modules. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow [Semantic Versioning](https://semver.org/). Before version 1.0, a minor release can include breaking changes.

Each entry names the platform it affects. A breaking entry says what to do before you apply the new version.

## Unreleased

### Breaking

- **AWS:** the `lambda_runtime` variable accepts only `python3.11` or later. If you set an older runtime, change it before you apply.
- **AWS:** the Lambda function requires AWS provider 5.32.0 or later. Run `tofu init -upgrade` if your lock file pins an older provider.
- **AWS:** the Lambda function writes JSON logs. Update CloudWatch metric filters, subscription filters, or log queries that match the old text output.
- **AWS:** an ECS API error now returns HTTP `502` from API Gateway instead of `500` with the error text. Scalr retries either status.

### Added

- **AWS:** the Lambda function passes the webhook `Idempotency-Key` header to ECS `RunTask` as `clientToken`. Webhook retries for the same agent task no longer start extra Fargate tasks.

### Fixed

- **AWS:** `tofu apply` deploys changes to the Lambda function code. Before this fix, the function kept the code from its first deployment.
- **AWS:** a webhook returns `503` when ECS cannot place the task. Before this fix, it returned `200` and Scalr did not retry.
- **AWS:** the Lambda function no longer logs the request headers, which included the API key.

### Documentation

- **Azure:** the README states that the module does not deduplicate webhook retries. The Container Apps Job start API has no idempotency key, so a retry can start an extra agent that finds no run and exits.
