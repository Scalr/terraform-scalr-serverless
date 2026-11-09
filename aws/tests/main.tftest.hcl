# Plan-only tests of the AWS child modules with mocked providers: no AWS credentials needed.

mock_provider "aws" {
  # The provider validates these arguments even when the values come from mocks.
  mock_resource "aws_api_gateway_rest_api" {
    defaults = { execution_arn = "arn:aws:execute-api:us-east-1:123456789012:mock" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

mock_provider "http" {}

# The archive reads the handler from path.root, which is the module under test here.
mock_provider "archive" {}

variables {
  name                   = "scalr-agent-pool-api"
  environment            = "prod"
  lambda_invoke_arn      = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:scalr-agent/invocations"
  lambda_function_name   = "scalr-agent"
  additional_allowed_ips = ["192.0.2.1/32"]
  allow_all_ingress      = false

  # Inputs of the Lambda module runs.
  function_name       = "scalr-agent"
  cluster_name        = "scalr-agent-pool-cluster"
  task_definition_arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/scalr-agent-run:1"
  security_group_id   = "sg-0123456789abcdef0"
  subnet_ids          = ["subnet-a", "subnet-b"]
  source_file         = "lambda_function.py"
  handler             = "lambda_function.lambda_handler"
  runtime             = "python3.13"
  timeout             = 30
  memory_size         = 128
}

run "scalr_allowlist_is_parsed_into_cidrs" {
  command = plan

  module {
    source = "../modules/common/scalr-ips"
  }

  override_data {
    target = data.http.scalr_allowlist
    values = { response_body = "192.0.2.1\n192.0.2.2\n" }
  }

  assert {
    condition     = output.allowed_ips == ["192.0.2.1/32", "192.0.2.2/32"]
    error_message = "The Scalr allowlist must become one /32 CIDR per line."
  }
}

run "webhook_requires_api_key_and_scalr_ips" {
  command = plan

  module {
    source = "./modules/api-gateway"
  }

  assert {
    condition     = aws_api_gateway_method.post_method.api_key_required
    error_message = "The webhook method must require an API key."
  }

  assert {
    condition     = length(aws_api_gateway_rest_api_policy.scalr_ip_restriction) == 1
    error_message = "The IP restriction policy must exist by default."
  }
}

run "allow_all_ingress_removes_ip_restriction" {
  command = plan

  module {
    source = "./modules/api-gateway"
  }

  variables {
    allow_all_ingress = true
  }

  assert {
    condition     = length(aws_api_gateway_rest_api_policy.scalr_ip_restriction) == 0
    error_message = "allow_all_ingress must remove the IP restriction policy."
  }
}

run "lambda_targets_the_agent_task" {
  command = plan

  module {
    source = "./modules/lambda"
  }

  assert {
    condition = aws_lambda_function.scalr_webhook.environment[0].variables == tomap({
      CLUSTER         = "scalr-agent-pool-cluster"
      TASK_DEFINITION = "arn:aws:ecs:us-east-1:123456789012:task-definition/scalr-agent-run:1"
      SECURITY_GROUP  = "sg-0123456789abcdef0"
      SUBNET_IDS      = "subnet-a,subnet-b"
    })
    error_message = "The Lambda function must receive the agent cluster, task definition, and network."
  }

  assert {
    condition     = aws_lambda_function.scalr_webhook.logging_config[0].log_format == "JSON"
    error_message = "The Lambda function must write JSON logs to keep structured fields."
  }
}

run "lambda_rejects_runtimes_before_python_3_11" {
  command = plan

  module {
    source = "./modules/lambda"
  }

  variables {
    runtime = "python3.10"
  }

  expect_failures = [var.runtime]
}
