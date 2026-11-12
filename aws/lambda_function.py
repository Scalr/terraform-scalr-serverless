"""AWS Lambda handler that starts an ECS Fargate task for each Scalr webhook delivery."""

from __future__ import annotations

import hashlib
import json
import logging
import os
from typing import TYPE_CHECKING, TypedDict

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

if TYPE_CHECKING:
    from types_boto3_ecs import ECSClient

LOG = logging.getLogger(__name__)

# One short attempt keeps the response within Scalr's 15-second webhook timeout.
ECS: ECSClient = boto3.client(
    "ecs",
    config=Config(connect_timeout=2, read_timeout=5, retries={"total_max_attempts": 1}),
)


class ApiGatewayProxyEvent(TypedDict, total=False):
    """The part of an API Gateway REST proxy event that the handler reads."""

    headers: dict[str, str] | None


class TaskRequested(TypedDict):
    taskArn: str


class WebhookError(TypedDict):
    error: str


class ApiGatewayProxyResponse(TypedDict):
    statusCode: int
    headers: dict[str, str]
    body: str


def respond(status_code: int, body: TaskRequested | WebhookError) -> ApiGatewayProxyResponse:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event: ApiGatewayProxyEvent, _context: object) -> ApiGatewayProxyResponse:
    """Request one ECS task per Idempotency-Key and return 202 once ECS accepts the launch."""
    # Header names are case-insensitive, and API Gateway keeps the sender's casing.
    headers = {name.lower(): value for name, value in (event.get("headers") or {}).items()}
    idempotency_key = headers.get("idempotency-key")
    if not idempotency_key:
        LOG.warning("Rejected webhook without Idempotency-Key")
        return respond(400, {"error": "Idempotency-Key header is required"})
    log_fields = {"idempotency_key": idempotency_key}

    try:
        result = ECS.run_task(
            cluster=os.environ["CLUSTER"],
            taskDefinition=os.environ["TASK_DEFINITION"],
            launchType="FARGATE",
            count=1,
            # ECS returns the original task for a token it has already accepted.
            clientToken=hashlib.sha256(idempotency_key.encode()).hexdigest(),
            networkConfiguration={
                "awsvpcConfiguration": {
                    "subnets": os.environ["SUBNET_IDS"].split(","),
                    "securityGroups": [os.environ["SECURITY_GROUP"]],
                    "assignPublicIp": "ENABLED",
                }
            },
        )
    except (BotoCoreError, ClientError):
        LOG.exception("ECS RunTask request failed", extra=log_fields)
        return respond(502, {"error": "ECS RunTask request failed"})

    if result["failures"] or not result["tasks"]:
        LOG.error(
            "ECS could not launch the task", extra={**log_fields, "failures": result["failures"]}
        )
        return respond(502, {"error": "ECS could not launch the task"})

    task_arn = result["tasks"][0]["taskArn"]
    LOG.info("ECS task requested", extra={**log_fields, "task_arn": task_arn})
    return respond(202, {"taskArn": task_arn})
