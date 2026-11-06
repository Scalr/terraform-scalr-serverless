"""Scalr webhook handler: starts one ECS Fargate task per webhook delivery.

Scalr delivers each webhook up to 3 times with the same ``Idempotency-Key``
header (the agent task ID). The key is passed to ``RunTask`` as ``clientToken``
so that ECS starts a single task for all deliveries of one key. ECS remembers
a client token for up to 24 hours per cluster.
"""

import hashlib
import json
import os
import re

import boto3

ecs = boto3.client("ecs")

IDEMPOTENCY_HEADER = "Idempotency-Key"

# ECS RunTask clientToken: 1-64 characters in the ASCII range 33-126.
CLIENT_TOKEN_RE = re.compile(r"^[\x21-\x7e]{1,64}$")

# ECS replays the cached result of the first RunTask for a client token, so a
# placement failure (no task, only ``failures``) would otherwise be replayed to
# every retry. Each attempt uses its own token derived from the key, and every
# delivery walks the same attempt chain, so a key still starts at most one task.
MAX_PLACEMENT_ATTEMPTS = 3


def get_header(headers, name):
    """Case-insensitive header lookup (API Gateway keeps the sender's casing)."""
    name = name.lower()
    for key, value in (headers or {}).items():
        if key.lower() == name:
            return value
    return None


def client_token(idempotency_key, attempt):
    """Map an Idempotency-Key to a valid ECS clientToken for the given attempt."""
    if attempt == 0 and CLIENT_TOKEN_RE.match(idempotency_key):
        return idempotency_key
    digest = hashlib.sha256(f"{idempotency_key}#{attempt}".encode())
    return digest.hexdigest()


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def log(**fields):
    print(json.dumps(fields, default=str))


def lambda_handler(event, context):
    idempotency_key = (get_header(event.get("headers"), IDEMPOTENCY_HEADER) or "").strip()
    log(requestId=context.aws_request_id, idempotencyKey=idempotency_key or None)

    run_task_args = {
        "cluster": os.environ["CLUSTER"],
        "launchType": "FARGATE",
        "taskDefinition": os.environ["TASK_DEFINITION"],
        "count": 1,
        "networkConfiguration": {
            "awsvpcConfiguration": {
                "subnets": os.environ["SUBNET_IDS"].split(","),
                "securityGroups": [os.environ["SECURITY_GROUP"]],
                "assignPublicIp": "ENABLED",
            }
        },
    }

    attempts = MAX_PLACEMENT_ATTEMPTS if idempotency_key else 1
    failures = []

    for attempt in range(attempts):
        if idempotency_key:
            run_task_args["clientToken"] = client_token(idempotency_key, attempt)

        try:
            result = ecs.run_task(**run_task_args)
        except ecs.exceptions.ConflictException as exc:
            # The token is already bound to a RunTask with different parameters
            # (for example the task definition revision changed between two
            # deliveries). A task for this key already exists, so do not start
            # another one.
            existing = exc.response.get("resourceIds", [])
            log(
                requestId=context.aws_request_id,
                idempotencyKey=idempotency_key,
                status="duplicate",
                tasks=existing,
            )
            return response(
                200,
                {
                    "status": "duplicate",
                    "idempotencyKey": idempotency_key,
                    "tasks": existing,
                },
            )
        except Exception as exc:  # Any ECS error must return a non-2xx status.
            log(
                requestId=context.aws_request_id,
                idempotencyKey=idempotency_key,
                status="error",
                error=str(exc),
            )
            return response(500, {"status": "error", "message": str(exc)})

        tasks = [task["taskArn"] for task in result.get("tasks", [])]
        if tasks:
            log(
                requestId=context.aws_request_id,
                idempotencyKey=idempotency_key,
                status="started",
                attempt=attempt,
                tasks=tasks,
            )
            return response(
                200,
                {
                    "status": "started",
                    "idempotencyKey": idempotency_key or None,
                    "tasks": tasks,
                },
            )

        failures = result.get("failures", [])
        log(
            requestId=context.aws_request_id,
            idempotencyKey=idempotency_key,
            status="placement-failed",
            attempt=attempt,
            failures=failures,
        )

    # Non-2xx so that Scalr retries the delivery.
    return response(
        503,
        {
            "status": "error",
            "message": "ECS did not place the task",
            "failures": failures,
        },
    )
