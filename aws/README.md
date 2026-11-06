# AWS Serverless Agent Pool

Deploys a Scalr serverless agent pool on AWS. Each Terraform or OpenTofu run executes in its own ECS Fargate task.

Product documentation: [Serverless agent pools](https://docs.scalr.io/docs/serverless-agents-pools).

## Architecture

Solid arrows show how a webhook starts an agent and how the agent accesses its cache. The dotted arrow shows the agent's separate connection back to Scalr during the run.

```mermaid
---
config:
  flowchart:
    nodeSpacing: 24
    rankSpacing: 24
    padding: 8
---
flowchart LR
    accTitle: AWS serverless agent pool request flow
    accDescr: Scalr sends a webhook to API Gateway. API Gateway checks the API key and, by default, the source IP, then invokes Lambda. Lambda calls ECS RunTask to start a single-run Fargate task. The agent mounts the EFS cache and connects back to Scalr to execute the run.
    scalr[Scalr] -- "webhook" --> apigw[API Gateway<br/>authenticates webhook]
    apigw --> lambda[Lambda<br/>starts task]
    lambda --> ecs[ECS Fargate<br/>runs Scalr agent]
    ecs -- "mounts" --> efs[(EFS<br/>stores downloads)]
    ecs -. "connects back" .-> scalr
```

API Gateway authenticates each webhook using the API key in the `x-api-key` header and, by default, checks that the source IP is on the Scalr allowlist. It then invokes Lambda, which calls ECS `RunTask` to start a Fargate task with the Scalr agent in single-run mode (`SCALR_AGENT_SINGLE=true`). The agent connects to Scalr, executes the run, and exits. The EFS file system keeps providers and modules between runs, so later runs skip those downloads.

### Webhook delivery and idempotency

Scalr delivers each webhook at least once, with the agent task ID in the `Idempotency-Key` header. It retries a delivery that times out, fails to connect, or returns a non-`2xx` status, up to 3 attempts in total. See the [webhook reference](https://docs.scalr.io/docs/serverless-webhooks#response-and-retries). An endpoint that does not deduplicate on that header can start an extra agent container for every retry.

The Lambda function passes the SHA-256 hash of `Idempotency-Key` to ECS `RunTask` as `clientToken`. ECS remembers a client token for up to 24 hours per cluster and returns the original task for repeated calls, so one key starts at most one Fargate task. The function follows the handler in the [manual setup guide](https://docs.scalr.io/docs/serverless-aws-fargate).

The function returns:

| Status | Meaning |
|---|---|
| `202` | ECS accepted the launch, or a task for this key already exists. The body has the `taskArn` |
| `400` | The request has no `Idempotency-Key` header. The function starts no task |
| `502` | The ECS `RunTask` request failed, or ECS could not launch the task. Scalr retries |

ECS also remembers a launch failure for the client token. A retry with the same `Idempotency-Key` returns the same `502` without a new launch attempt.

## Prerequisites

- Terraform 1.0 or later, or OpenTofu.
- The AWS CLI, authenticated to an account where you can create VPC, API Gateway, Lambda, ECS, EFS, IAM, and Secrets Manager resources.
- A Scalr account and an API token. The Scalr provider reads them from the `SCALR_HOSTNAME` and `SCALR_TOKEN` environment variables.

## Quick start

Every variable has a default. Create `terraform.tfvars` only to override one, then apply:

```bash
cd aws
tofu init
tofu apply
```

The apply creates the AWS resources and the Scalr agent pool, and registers the webhook endpoint with Scalr.

## Configuration

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region | `us-east-1` |
| `allow_all_ingress` | Accept webhooks from any IP address instead of the Scalr IP allowlist. Use only for testing | `false` |
| `vpc_name` | VPC name prefix | `scalr-agent` |
| `ecs_cluster_name` | ECS cluster name | `scalr-agent-pool-cluster` |
| `ecs_image` | Container image | `scalr/agent:latest` |
| `ecs_limit_cpu` | ECS task CPU units (1024 = 1 vCPU) | `2048` |
| `ecs_limit_memory` | ECS task memory (MB) | `4096` |
| `ecs_task_stop_timeout` | Seconds ECS waits for the agent to stop before it kills the container | `120` |
| `lambda_timeout` | Lambda timeout (seconds) | `30` |
| `lambda_memory_size` | Lambda memory (MB) | `128` |
| `lambda_runtime` | Lambda Python runtime. The handler requires `python3.11` or later | `python3.13` |

## Outputs

| Output | Description |
|---|---|
| `webhook_url` | API Gateway endpoint URL |
| `api_key` | API key for webhook authentication (sensitive) |
| `agent_pool_id` | Scalr agent pool ID |
| `agent_token` | Scalr agent token (sensitive) |
| `scalr_allowed_ips` | Scalr IP addresses that the API Gateway policy allows |

## What gets created

| Resource | Purpose |
|---|---|
| VPC and subnets | Network for the ECS tasks |
| API Gateway (REST API) | Webhook endpoint with API key authentication and IP restriction. HTTP APIs (API Gateway v2) do not support resource policies, API keys, or usage plans, so the module uses a REST API |
| Lambda function | Starts one ECS task per webhook delivery |
| ECS cluster and task definition | Run the Scalr agent container on Fargate |
| Secrets Manager secret | Holds the Scalr agent token. The task definition injects it as `SCALR_AGENT_TOKEN` |
| EFS file system and access points | Persistent Terraform provider and module cache |
| Security groups | Network access control for ECS and EFS |

## Security

- **API key authentication**: every webhook request needs the `x-api-key` header.
- **Idempotent delivery**: repeated deliveries with the same `Idempotency-Key` start one task (ECS `clientToken`).
- **IP restriction**: an API Gateway resource policy accepts requests only from the Scalr IP addresses listed at `scalr.io/.well-known/allowlist.txt`. Set `allow_all_ingress = true` to disable the restriction for testing.
- **Token storage**: the Scalr agent token lives in AWS Secrets Manager. The task definition references it with `valueFrom`, so the token does not appear in the task definition as plain text.
- **VPC isolation**: ECS tasks run in dedicated subnets with security groups.
- **EFS encryption**: EFS encrypts data at rest.

## Cost estimate

Estimated monthly cost for 1,000 to 2,000 runs per month:

| Resource | Cost |
|---|---|
| API Gateway | About $1 |
| Lambda | Under $1 |
| ECS Fargate | Billed per vCPU-second and GB-second while tasks run |
| EFS | Billed per GB stored |
| **Total** | **$5 to $20**, depending on run duration |

## Troubleshooting

### Test the webhook manually

```bash
WEBHOOK_URL=$(tofu output -raw webhook_url)
API_KEY=$(tofu output -raw api_key)
curl -s -X POST "$WEBHOOK_URL" \
  -H "x-api-key: $API_KEY" \
  -H "Idempotency-Key: manual-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

A successful request returns `202` with the ECS task ARN. Send the request twice with the same `Idempotency-Key`. The second call returns the same task ARN and does not start a second task.

### Check ECS task status

```bash
aws ecs list-tasks --cluster scalr-agent-pool-cluster --desired-status RUNNING
aws ecs describe-tasks --cluster scalr-agent-pool-cluster --tasks <task-arn>
```

### View ECS task logs

```bash
aws logs filter-log-events --log-group-name /ecs/scalr-agent-pool-cluster
```

### Check Lambda invocations

The function writes JSON logs. Each record of a webhook delivery has the `idempotency_key` field, so you can find the records for one Scalr agent task:

```bash
aws logs filter-log-events --log-group-name /aws/lambda/scalr-agent \
  --filter-pattern '{ $.idempotency_key = "<agent-task-id>" }'
```

### View Scalr IP allowlist

```bash
curl -s https://scalr.io/.well-known/allowlist.txt
```

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `403` on the webhook | The source IP is not in the Scalr allowlist | Compare the source IP with the allowlist. For testing, set `allow_all_ingress = true` |
| `403` with a valid API key | The key does not match the deployed one | Read the key again: `tofu output -raw api_key` |
| Lambda timeout | The ECS `RunTask` call took longer than `lambda_timeout` | Increase `lambda_timeout` |
| Webhook returns `202` but no new task starts | A task for this `Idempotency-Key` started within the last 24 hours | Expected. Send a new key to start another task |
| `ECS could not launch the task` in Lambda logs | ECS rejected the launch | Read the `reason` in the logged `failures` list |
| `ConflictException` in Lambda logs | A retry reused a client token with different launch parameters, for example after a new task definition revision | Keep launch settings stable while Scalr retries. The webhook returns `502` |
| ECS task fails to start | Image pull error or resource limits | Check the CloudWatch logs and verify that the image exists |
| Slow first run | The agent downloads providers into the empty EFS cache | Expected. Later runs use the cached providers |
