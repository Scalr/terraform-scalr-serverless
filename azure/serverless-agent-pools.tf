# Optional: additional Scalr agent pools sharing the same Container Apps environment

# module "staging_agent_pool" {
#   source = "../modules/scalr/serverless-agent-pool"
#
#   agent_pool_name = "staging-azure-serverless"
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
