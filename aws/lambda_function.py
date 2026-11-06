"""AWS Lambda handler that starts an ECS Fargate task for each Scalr webhook delivery."""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from typing import TYPE_CHECKING, Literal, NotRequired, TypedDict

import boto3

if TYPE_CHECKING:
    from types_boto3_ecs import ECSClient
    from types_boto3_ecs.type_defs import FailureTypeDef, RunTaskRequestTypeDef

LOG = logging.getLogger(__name__)

ECS: ECSClient = boto3.client("ecs")

IDEMPOTENCY_HEADER = "idempotency-key"

# ECS accepts a clientToken of 1 to 64 ASCII characters in the range 33-126.
CLIENT_TOKEN_PATTERN = re.compile(r"[\x21-\x7e]{1,64}")


class ApiGatewayProxyEvent(TypedDict):
    """The part of an API Gateway REST proxy event that the handler reads."""

    headers: dict[str, str] | None


class WebhookResult(TypedDict):
    """JSON body returned to Scalr."""

    status: Literal["started", "duplicate", "error"]
    idempotencyKey: str | None
    tasks: NotRequired[list[str]]
    failures: NotRequired[list[FailureTypeDef]]


class ApiGatewayProxyResponse(TypedDict):
    statusCode: int
    headers: dict[str, str]
    body: str


def build_client_token(idempotency_key: str) -> str:
    """Return the key itself if ECS accepts it as a clientToken, otherwise its SHA-256 digest."""
    if CLIENT_TOKEN_PATTERN.fullmatch(idempotency_key):
        return idempotency_key
    return hashlib.sha256(idempotency_key.encode()).hexdigest()


def respond(status_code: int, result: WebhookResult) -> ApiGatewayProxyResponse:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(result),
    }


def lambda_handler(event: ApiGatewayProxyEvent, _context: object) -> ApiGatewayProxyResponse:
    """Start one ECS task per Idempotency-Key; requests without the key always start a task.

    An ECS API error propagates, so API Gateway returns 502 and Scalr retries the delivery.
    """
    idempotency_key: str | None = None
    for name, value in (event["headers"] or {}).items():
        # Header names are case-insensitive, and API Gateway keeps the sender's casing.
        if name.lower() == IDEMPOTENCY_HEADER and value.strip():
            idempotency_key = value.strip()
    log_fields = {"idempotency_key": idempotency_key}

    request: RunTaskRequestTypeDef = {
        "cluster": os.environ["CLUSTER"],
        "taskDefinition": os.environ["TASK_DEFINITION"],
        "launchType": "FARGATE",
        "count": 1,
        "networkConfiguration": {
            "awsvpcConfiguration": {
                "subnets": os.environ["SUBNET_IDS"].split(","),
                "securityGroups": [os.environ["SECURITY_GROUP"]],
                "assignPublicIp": "ENABLED",
            }
        },
    }
    if idempotency_key:
        # ECS returns the first result for a token it has seen in the last 24 hours.
        request["clientToken"] = build_client_token(idempotency_key)

    try:
        result = ECS.run_task(**request)
    except ECS.exceptions.ConflictException:
        # ECS raises this when the token belongs to a RunTask with other parameters,
        # for example after a new task definition revision.
        LOG.info("ECS task already started for idempotency key", extra=log_fields)
        return respond(200, {"status": "duplicate", "idempotencyKey": idempotency_key})

    task_arns = [task["taskArn"] for task in result["tasks"] if "taskArn" in task]
    if not task_arns:
        LOG.error(
            "ECS did not place the task", extra={**log_fields, "failures": result["failures"]}
        )
        return respond(
            503,
            {"status": "error", "idempotencyKey": idempotency_key, "failures": result["failures"]},
        )

    LOG.info("ECS task started", extra={**log_fields, "task_arns": task_arns})
    return respond(
        200, {"status": "started", "idempotencyKey": idempotency_key, "tasks": task_arns}
    )
