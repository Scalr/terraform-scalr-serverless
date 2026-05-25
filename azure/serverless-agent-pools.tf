# Optional: additional Scalr serverless agent pools wired to the same Logic App webhook

# module "staging_agent_pool" {
#   source = "../modules/scalr/serverless-agent-pool"
#
#   agent_pool_name = "staging-azure-serverless"
#   webhook_url     = module.webhook.url
#   webhook_headers = [
#     {
#       name      = "Content-Type"
#       value     = "application/json"
#       sensitive = false
#     },
#     {
#       name      = "x-environment"
#       value     = "staging"
#       sensitive = false
#     }
#   ]
# }
