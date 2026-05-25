# Scalr Serverless Agent Pool Infrastructure

This Terraform configuration deploys serverless infrastructure for running Scalr agent pools on **AWS** or **Azure**, featuring:

- **Secure API Gateway** with Scalr.io IP restrictions
- **Lambda function** for triggering ECS tasks
- **ECS Fargate tasks** with persistent EFS storage for Terraform cache
- **VPC networking** with proper security groups
- **EFS storage** for Terraform provider and module caching

## Architecture

**AWS**

```
Scalr.io Webhook → API Gateway → Lambda → ECS Fargate (with EFS cache)
```

**Azure**

```
Scalr.io Webhook → Logic App → Container Apps Job (with Azure Files cache)
```

Uses Azure Container Apps Jobs for fast cold starts (~5-15s) vs ~2min with ACI. A lightweight Consumption Logic App receives the Scalr webhook and starts a job execution via the ARM API. Images are mirrored to ACR to avoid Docker Hub rate limits.

## Features

- ✅ **IP-based security**: Only allows traffic from official Scalr.io IP addresses
- ✅ **API key authentication**: Additional security layer for webhook endpoint
- ✅ **Persistent caching**: EFS storage for Terraform providers and modules
- ✅ **Configurable timeouts**: Lambda and ECS task timeout controls
- ✅ **Auto-scaling**: ECS tasks scale based on webhook triggers
- ✅ **Official IP source**: Automatically fetches Scalr IP allowlist from `scalr.io/.well-known/allowlist.txt`

## Prerequisites

- Terraform >= 1.0 (OpenTofu supported)
- Scalr account and API access (`SCALR_HOSTNAME`, `SCALR_TOKEN`)
- **AWS**: AWS CLI configured with appropriate permissions
- **Azure**: Azure CLI logged in (`az login`) and subscription access

## Quick Start (AWS)

1. **Clone and configure**:
   ```bash
   git clone https://github.com/Scalr/terraform-scalr-aws-serverless
   cd terraform-scalr-aws-serverless
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit variables**:
   ```hcl
   # terraform.tfvars
   aws_region = "us-east-1"
   allow_all_ingress = false  # Enable Scalr IP restrictions
   
   # Customize other variables as needed
   ecs_limit_cpu    = 2048
   ecs_limit_memory = 4096
   ```

3. **Deploy infrastructure**:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

4. **Get webhook URL and API key**:
   ```bash
   tofu output webhook_url
   tofu output api_key
   ```

5. **Configure in Scalr** (if not using automated agent pool wiring):
   - Agent pool webhook URL and API key are configured automatically when `webhook_url` is set on the agent pool module
   - Test the webhook functionality

## Quick Start (Azure)

1. **Configure variables**:
   ```bash
   cd azure
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Deploy**:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

3. **Verify**:
   ```bash
   tofu output agent_pool_id
   tofu output container_app_job
   ```

The Azure stack creates a Scalr agent pool, an Azure Container Apps environment with a Job, and an ACR mirror of the agent image. When Scalr triggers a run, the Container Apps Job spins up an agent container in ~5-15 seconds (vs ~2 minutes with ACI). Azure Files provides persistent Terraform cache across runs.

Additional agent pools can be added in `azure/serverless-agent-pools.tf`.

## Future Integration

The architecture supports future bidirectional integration where the agent pool can be configured with the API Gateway details:

1. **Uncomment the webhook configuration** in `main.tf`:
   ```hcl
   module "agent_pool" {
     source = "./modules/scalr/agent-pool"
     
     webhook_url = module.api_gateway.url
     webhook_headers = [
       {
         name      = "x-api-key"
         value     = module.api_gateway.api_key
         sensitive = true
       },
       {
         name      = "Content-Type"
         value     = "application/json"
         sensitive = false
       }
     ]
   }
   ```

2. Serverless webhook configuration is enabled via `api_gateway_url` and `header` blocks on `scalr_agent_pool` (see `modules/scalr/agent-pool`).

## Security Configuration

### IP Restrictions

The system automatically uses official Scalr.io IP addresses from their public allowlist:
- **Source**: `https://scalr.io/.well-known/allowlist.txt`
- **Applied to**: API Gateway resource policy
- **Control**: Set `allow_all_ingress = false` to enable restrictions

### Authentication

- **API Key**: Required for all webhook requests
- **IP Filtering**: Only Scalr.io IPs can reach the endpoint
- **VPC Security**: ECS tasks run in isolated VPC subnets

## Persistent Storage

EFS provides persistent caching for:
- **Terraform providers** (`/providers-cache`)
- **Terraform modules** (`/terraform-cache`)

Environment variables automatically configured:
- `TF_PLUGIN_CACHE_DIR=/terraform-cache`
- `TF_DATA_DIR=/providers-cache`

## Configuration Variables

### Core Settings
| Variable            | Description                               | Default       |
|---------------------|-------------------------------------------|---------------|
| `aws_region`        | AWS region for deployment                 | `us-east-1`   |
| `allow_all_ingress` | Disable IP restrictions (not recommended) | `false`       |
| `vpc_name`          | VPC name prefix                           | `scalr-agent` |

### ECS Settings
| Variable                | Description               | Default                    |
|-------------------------|---------------------------|----------------------------|
| `ecs_limit_cpu`         | ECS task CPU units        | `2048`                     |
| `ecs_limit_memory`      | ECS task memory (MB)      | `4096`                     |
| `ecs_image`             | Container image           | `scalr/agent:latest` |
| `ecs_task_stop_timeout` | Graceful shutdown timeout | `120`                      |

### Lambda Settings
| Variable             | Description              | Default      |
|----------------------|--------------------------|--------------|
| `lambda_timeout`     | Lambda timeout (seconds) | `30`         |
| `lambda_memory_size` | Lambda memory (MB)       | `128`        |
| `lambda_runtime`     | Python runtime version   | `python3.11` |

## Outputs

| Output               | Description                        |
|----------------------|------------------------------------|
| `webhook_url`        | API Gateway webhook endpoint       |
| `api_key`            | Authentication key (sensitive)     |
| `agent_pool_id`      | Scalr agent pool ID                |
| `agent_token`        | Scalr agent token (sensitive)      |
| `scalr_allowed_ips`  | Official Scalr.io IP addresses     |

## Monitoring and Troubleshooting

### Check Security Status
```bash
# View current IP restrictions
tofu output scalr_allowed_ips

# Check official Scalr IPs directly
curl -s https://scalr.io/.well-known/allowlist.txt

# Check API Gateway security
aws logs filter-log-events --log-group-name API-Gateway-Execution-Logs*
```

### Test Webhook
```bash
curl -X POST [webhook_url] \
  -H "x-api-key: [api_key]" \
  -H "Content-Type: application/json" \
  -d '{"test": "webhook"}'
```

### ECS Task Logs
```bash
aws logs filter-log-events --log-group-name /ecs/scalr-agent-pool-cluster
```

## Customization

### Scalr Workspace (Optional)
Uncomment and customize the workspace configuration in `main.tf`:

```hcl
data "scalr_environment" "example" {
  name = "your-environment-name"
}

resource "scalr_workspace" "example" {
  environment_id = data.scalr_environment.example.id
  name           = "your-workspace-name"
  agent_pool_id  = module.agent_pool.agent_pool_id
  # ... other settings
}
```

### Custom Container Image
Build your own image with pre-cached providers:

```dockerfile
FROM scalr/agent:latest
# Add your customizations
COPY providers/ /terraform-cache/
```

## Cost Optimization

- **EFS**: Pay only for storage used
- **Lambda**: Pay per invocation (typically < $1/month)
- **ECS Fargate**: Pay only when tasks are running
- **API Gateway**: Pay per request

Estimated monthly cost for moderate usage: **$5-20**

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- **Issues**: GitHub Issues
- **Scalr Support**: support@scalr.com
- **AWS Support**: Through your AWS support plan