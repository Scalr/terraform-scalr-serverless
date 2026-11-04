# Azure Serverless Agent Pool

Deploys a Scalr serverless agent pool on Azure using Container Apps Jobs for fast, on-demand Terraform/OpenTofu runs.

## Architecture

```
Scalr.io Webhook
      |
      v
API Management (Consumption) ── authenticates via subscription key
      |
      v
Azure Container Apps Job ── runs scalr/agent with SCALR_SINGLE=true
      |
      v
Azure Files ── persistent Terraform provider & module cache
```

When Scalr triggers a run, the webhook hits APIM, which starts a Container Apps Job execution via managed identity. The agent container starts in ~5-15 seconds, connects to Scalr, executes the run, and exits. Azure Files provides persistent cache so subsequent runs skip provider/module downloads.

### Webhook delivery and idempotency

Scalr delivers each webhook at least once: up to 3 attempts with a 15 s read timeout, all carrying the same `Idempotency-Key` header (the agent task ID). The endpoint must dedupe on that header, otherwise every retry starts an idle agent container that you pay for.

APIM Consumption has no built-in cache, so the policy uses the storage account as the key store. Before it starts a job, the policy creates a blob named after the `Idempotency-Key` in the `idempotency-keys` container with `If-None-Match: *`. Blob creation is atomic, so only one delivery claims the key:

1. The claim succeeds: the policy starts the job and returns the Container Apps answer.
2. The key already exists and is younger than `idempotency_window_minutes` (default 60): the policy returns `200` with `{"status": "duplicate"}` and starts nothing.
3. The job start fails: the policy deletes the key and returns the non-2xx answer, so Scalr retries.
4. The key store is unreachable: the policy returns `503`, so Scalr retries.

Keys older than `idempotency_window_minutes` can be claimed again. A lifecycle rule deletes key blobs one day after creation. A delivery without the header always starts a job.

## Prerequisites

- Terraform >= 1.0 or OpenTofu
- Azure CLI logged in (`az login`) or another [authentication method](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure) configured
- Scalr account with API access (`SCALR_HOSTNAME` and `SCALR_TOKEN` environment variables)

## Quick Start

```bash
cd azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to match your environment
tofu init
tofu apply
```

The first deploy takes ~10-15 minutes (APIM provisioning). Subsequent applies are fast.

## Configuration

| Variable | Description | Default |
|---|---|---|
| `azure_location` | Azure region | `eastus` |
| `resource_group_name` | Resource group name | `scalr-serverless-rg` |
| `name_prefix` | Prefix for all resource names | `scalr-agent` |
| `agent_pool_name` | Scalr agent pool name | `azure-serverless` |
| `container_image` | Agent container image | `scalr/agent:latest` |
| `container_cpu` | CPU cores per job execution | `2` |
| `container_memory_gb` | Memory (GB) per job execution | `4` |
| `job_timeout` | Max run time per job (seconds) | `3600` |
| `max_parallel_runs` | Max concurrent job executions | `10` |
| `idempotency_window_minutes` | How long an `Idempotency-Key` blocks repeated deliveries from starting another job | `60` |

## Outputs

| Output | Description |
|---|---|
| `webhook_url` | APIM endpoint URL (passed to Scalr automatically) |
| `api_key` | APIM subscription key (sensitive) |
| `agent_pool_id` | Scalr agent pool ID |
| `container_app_job` | Container Apps Job name |
| `resource_group_name` | Azure resource group name |
| `storage_account_name` | Storage account for the cache and the idempotency keys |

## What Gets Created

| Resource | Purpose |
|---|---|
| Resource Group | Contains all resources |
| VNet + Subnet | Network isolation for Container Apps (with NSG) |
| Container Apps Environment | Hosting environment for jobs |
| Container Apps Job | Runs the Scalr agent on demand |
| API Management (Consumption) | Webhook endpoint with API key auth |
| Container Registry (Basic) | Mirrors the agent image from Docker Hub |
| Storage Account + File Shares | Persistent Terraform provider & module cache |
| Blob Container `idempotency-keys` | Webhook dedupe keys, expired by a lifecycle rule after 1 day |

## Cost Estimate

For typical usage (1,000-2,000 runs/month):

| Resource | Cost |
|---|---|
| API Management (Consumption) | Free (first 1M calls/month included) |
| Container Apps Job | ~$0.000012/vCPU-sec, ~$0.000002/GiB-sec (pay per execution) |
| Container Registry (Basic) | ~$5/month |
| Storage Account (50 GB LRS) | ~$1/month |
| **Total** | **~$10-20/month** depending on run duration |

Container Apps Jobs have a free grant of 180,000 vCPU-seconds and 360,000 GiB-seconds per subscription per month.

## Troubleshooting

### Check job executions

```bash
az containerapp job execution list \
  --resource-group scalr-serverless-rg \
  --name scalr-agent-agent -o table
```

### View container logs

```bash
az containerapp logs show \
  --resource-group scalr-serverless-rg \
  --name scalr-agent-agent --type system
```

### Test the webhook manually

```bash
API_KEY=$(tofu output -raw api_key)
WEBHOOK_URL=$(tofu output -raw webhook_url)
curl -s -X POST "$WEBHOOK_URL" \
  -H "Ocp-Apim-Subscription-Key: $API_KEY" \
  -H "Idempotency-Key: manual-$(date +%s)" \
  -H "Content-Type: application/json" -d '{}'
```

A successful response returns HTTP 200 with the job execution ID. Send the same `Idempotency-Key` twice: the second call returns `{"status": "duplicate"}` and does not start a second execution.

### List claimed idempotency keys

```bash
az storage blob list --auth-mode login \
  --account-name $(tofu output -raw storage_account_name) \
  --container-name idempotency-keys -o table
```

### Stop a running execution

```bash
az rest --method POST --uri \
  "https://management.azure.com/subscriptions/{sub_id}/resourceGroups/scalr-serverless-rg/providers/Microsoft.App/jobs/scalr-agent-agent/executions/{execution_name}/stop?api-version=2024-03-01"
```

### Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| `MissingSubscriptionRegistration` | `Microsoft.App` not registered | Handled automatically by the provider (`resource_provider_registrations = "extended"`). If using a restricted service principal, register manually: `az provider register --namespace Microsoft.App` |
| 401 on webhook | API key mismatch | Re-read key: `tofu output -raw api_key` |
| Job starts but agent doesn't pick up run | Token mismatch or Scalr URL wrong | Check `SCALR_URL` and `SCALR_TOKEN` env vars in the job |
| Slow first webhook call (~5s) | APIM Consumption cold start | Normal on first call after idle period |
| `503` with `"Could not claim the idempotency key"` right after `tofu apply` | The APIM role assignment on the `idempotency-keys` container has not propagated yet | Wait a few minutes; Scalr retries the delivery |
| Webhook returns `{"status": "duplicate"}` but no execution runs | The `Idempotency-Key` was claimed within `idempotency_window_minutes` | Expected: an execution for that key was already started. Send a new key to start another one |

## Security

- **Webhook auth**: APIM subscription key in `Ocp-Apim-Subscription-Key` header (no secrets in URLs)
- **ARM API access**: APIM uses system-assigned managed identity to start jobs (scoped to the job resource only)
- **Key store access**: The same managed identity has `Storage Blob Data Contributor` on the `idempotency-keys` container only
- **Idempotent delivery**: Repeated deliveries with the same `Idempotency-Key` start one job execution
- **Registry**: ACR with admin credentials (Basic SKU); images pulled over Azure's internal network
- **Storage**: TLS 1.2 enforced, blob public access disabled, soft-delete enabled
- **Network**: Container Apps subnet with NSG, delegated to `Microsoft.App/environments`
