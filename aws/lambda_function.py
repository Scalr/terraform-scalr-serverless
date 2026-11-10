"""AWS Lambda handler that starts an ECS Fargate task for each Scalr webhook delivery."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import logging
import os
import re
from typing import TYPE_CHECKING, TypedDict

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

if TYPE_CHECKING:
    from types_boto3_ecs import ECSClient
    from types_boto3_ecs.type_defs import KeyValuePairTypeDef, TaskOverrideTypeDef

LOG = logging.getLogger(__name__)

LAUNCHER_VERSION = "0.1.0"
"""Reported to Scalr in the Scalr-Launcher-Version response header. Bump it with each release."""

AGENT_OPTION_NAME = re.compile(r"SCALR_AGENT_[A-Z0-9_]+")
RESERVED_AGENT_OPTIONS = frozenset({"SCALR_AGENT_TOKEN", "SCALR_AGENT_SINGLE"})
"""Set by the task definition. A webhook must not change the pool or the single-run mode."""

# One short attempt keeps the response within Scalr's 15-second webhook timeout.
ECS: ECSClient = boto3.client(
    "ecs",
    config=Config(connect_timeout=2, read_timeout=5, retries={"total_max_attempts": 1}),
)


class ApiGatewayProxyEvent(TypedDict, total=False):
    """The part of an API Gateway REST proxy event that the handler reads."""

    headers: dict[str, str] | None
    body: str | None
    isBase64Encoded: bool


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
        "headers": {"Content-Type": "application/json", "Scalr-Launcher-Version": LAUNCHER_VERSION},
        "body": json.dumps(body),
    }


def agent_environment(event: ApiGatewayProxyEvent) -> list[KeyValuePairTypeDef]:
    """Return the agent options from the webhook's `agent_environment` that may be set."""
    body = event.get("body") or "{}"
    try:
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode()
        options = json.loads(body).get("agent_environment") or {}
    except (binascii.Error, UnicodeDecodeError, ValueError, AttributeError):
        return []
    if not isinstance(options, dict):
        return []

    environment: list[KeyValuePairTypeDef] = []
    for name, value in options.items():
        if (
            not AGENT_OPTION_NAME.fullmatch(name)
            or name in RESERVED_AGENT_OPTIONS
            or not isinstance(value, str)
        ):
            LOG.warning("Ignored agent option from the webhook", extra={"option_name": name})
            continue
        environment.append({"name": name, "value": value})
    return environment


def lambda_handler(event: ApiGatewayProxyEvent, _context: object) -> ApiGatewayProxyResponse:
    """Request one ECS task per Idempotency-Key and return 202 once ECS accepts the launch."""
    # Header names are case-insensitive, and API Gateway keeps the sender's casing.
    headers = {name.lower(): value for name, value in (event.get("headers") or {}).items()}
    idempotency_key = headers.get("idempotency-key")
    if not idempotency_key:
        LOG.warning("Rejected webhook without Idempotency-Key")
        return respond(400, {"error": "Idempotency-Key header is required"})
    log_fields = {"idempotency_key": idempotency_key}

    # Scalr passes agent options, such as SCALR_AGENT_TASK_ID, with each webhook.
    overrides: TaskOverrideTypeDef = {}
    if environment := agent_environment(event):
        overrides = {
            "containerOverrides": [
                {"name": os.environ["CONTAINER_NAME"], "environment": environment}
            ]
        }

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
            overrides=overrides,
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
