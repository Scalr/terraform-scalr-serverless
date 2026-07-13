# AWS Serverless Agent Pool

Deploys a Scalr serverless agent pool on AWS using ECS Fargate for on-demand Terraform/OpenTofu runs.

## Architecture

```
Scalr.io Webhook
      |
      v
API Gateway (REST API) ── authenticates via x-api-key, restricts to Scalr IPs
      |
      v
Lambda ── starts an ECS Fargate task
      |
      v
ECS Fargate ── runs scalr/agent with SCALR_SINGLE=true
      |
      v
EFS ── persistent Terraform provider & module cache
```

When Scalr triggers a run, the webhook hits API Gateway, which invokes a Lambda function. Lambda starts an ECS Fargate task running the Scalr agent. The agent connects to Scalr, executes the run, and exits. EFS provides persistent cache so subsequent runs skip provider/module downloads.

## Prerequisites

- Terraform >= 1.0 or OpenTofu
- AWS CLI configured with appropriate permissions
- Scalr account with API access (`SCALR_HOSTNAME` and `SCALR_TOKEN` environment variables)

## Quick Start

```bash
cd aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
tofu init && tofu apply
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region | `us-east-1` |
| `allow_all_ingress` | Disable Scalr IP restrictions (not recommended) | `false` |
| `vpc_name` | VPC name prefix | `scalr-agent` |
| `ecs_cluster_name` | ECS cluster name | `scalr-agent-pool-cluster` |
| `ecs_image` | Container image | `scalr/agent:latest` |
| `ecs_limit_cpu` | ECS task CPU units (1024 = 1 vCPU) | `2048` |
| `ecs_limit_memory` | ECS task memory (MB) | `4096` |
| `ecs_task_stop_timeout` | Graceful shutdown timeout (seconds) | `120` |
| `lambda_timeout` | Lambda timeout (seconds) | `30` |
| `lambda_memory_size` | Lambda memory (MB) | `128` |
| `lambda_runtime` | Python runtime version | `python3.11` |

## Outputs

| Output | Description |
|---|---|
| `webhook_url` | API Gateway endpoint URL |
| `api_key` | API key for webhook authentication (sensitive) |
| `agent_pool_id` | Scalr agent pool ID |
| `agent_token` | Scalr agent token (sensitive) |
| `scalr_allowed_ips` | Official Scalr.io IP addresses |

## What Gets Created

| Resource | Purpose |
|---|---|
| VPC + Subnets | Network isolation for ECS tasks |
| API Gateway (REST) | Webhook endpoint with API key auth and IP restriction. A REST API is required — HTTP APIs (API Gateway v2) do not support the resource policies used for Scalr IP restriction or API keys/usage plans |
| Lambda Function | Lightweight trigger that starts ECS tasks |
| ECS Cluster + Task Definition | Runs the Scalr agent container on Fargate |
| Secrets Manager Secret | Stores the Scalr agent token, injected into the container as `SCALR_TOKEN` |
| EFS File System + Access Points | Persistent Terraform provider & module cache |
| Security Groups | Network access control for ECS and EFS |

## Security

- **API key authentication**: All webhook requests require an `x-api-key` header
- **IP restrictions**: API Gateway resource policy restricts access to official Scalr.io IP addresses (fetched from `scalr.io/.well-known/allowlist.txt`). Disable with `allow_all_ingress = true` for testing
- **Token storage**: The Scalr agent token is stored in AWS Secrets Manager (plaintext secret) and referenced by the task definition via `valueFrom` — it never appears as a plaintext environment variable in the task definition
- **VPC isolation**: ECS tasks run in dedicated subnets with security groups
- **EFS encryption**: Data at rest is encrypted by default

## Cost Estimate

For moderate usage (1,000-2,000 runs/month):

| Resource | Cost |
|---|---|
| API Gateway | ~$1/month |
| Lambda | < $1/month |
| ECS Fargate | Pay per vCPU/memory-second (only while tasks run) |
| EFS | Pay per GB stored |
| **Total** | **~$5-20/month** depending on run duration |

## Troubleshooting

### Test the webhook manually

```bash
WEBHOOK_URL=$(tofu output -raw webhook_url)
API_KEY=$(tofu output -raw api_key)
curl -s -X POST "$WEBHOOK_URL" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

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

```bash
aws logs filter-log-events --log-group-name /aws/lambda/scalr-agent
```

### View Scalr IP allowlist

```bash
curl -s https://scalr.io/.well-known/allowlist.txt
```

### Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| 403 on webhook | IP not in allowlist | Set `allow_all_ingress = true` for testing, or verify Scalr IPs |
| 403 with valid API key | API key mismatch | Re-read key: `tofu output -raw api_key` |
| Lambda timeout | ECS task takes too long to register | Increase `lambda_timeout` |
| ECS task fails to start | Image pull error or resource limits | Check CloudWatch logs, verify image exists |
| Slow first run | EFS + provider download | Subsequent runs use cached providers |
