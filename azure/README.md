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

## Outputs

| Output | Description |
|---|---|
| `webhook_url` | APIM endpoint URL (passed to Scalr automatically) |
| `api_key` | APIM subscription key (sensitive) |
| `agent_pool_id` | Scalr agent pool ID |
| `container_app_job` | Container Apps Job name |
| `resource_group_name` | Azure resource group name |

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
  -H "Content-Type: application/json" -d '{}'
```

A successful response returns HTTP 200 with the job execution ID.

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

## Security

- **Webhook auth**: APIM subscription key in `Ocp-Apim-Subscription-Key` header (no secrets in URLs)
- **ARM API access**: APIM uses system-assigned managed identity to start jobs (scoped to the job resource only)
- **Registry**: ACR with admin credentials (Basic SKU); images pulled over Azure's internal network
- **Storage**: TLS 1.2 enforced, blob public access disabled, soft-delete enabled
- **Network**: Container Apps subnet with NSG, delegated to `Microsoft.App/environments`
