import hashlib
import json
from collections.abc import Iterator

import botocore.exceptions
import pytest
from botocore.stub import Stubber

import lambda_function

RUN_TASK_REQUEST = {
    "cluster": "cluster",
    "taskDefinition": "task-definition",
    "launchType": "FARGATE",
    "count": 1,
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": ["subnet-a", "subnet-b"],
            "securityGroups": ["sg"],
            "assignPublicIp": "ENABLED",
        }
    },
}
STARTED = {"tasks": [{"taskArn": "arn:aws:ecs:task/1"}], "failures": []}


@pytest.fixture
def ecs() -> Iterator[Stubber]:
    with Stubber(lambda_function.ECS) as stubber:
        yield stubber
        stubber.assert_no_pending_responses()


def call_handler(headers: dict[str, str] | None) -> tuple[int, dict]:
    response = lambda_function.lambda_handler({"headers": headers}, None)
    return response["statusCode"], json.loads(response["body"])


@pytest.mark.parametrize(
    ("headers", "client_token"),
    [
        ({"Idempotency-Key": "task-1"}, "task-1"),
        ({"idempotency-key": " task-1 "}, "task-1"),
        ({"Idempotency-Key": "x" * 65}, hashlib.sha256(b"x" * 65).hexdigest()),
        ({}, None),
        (None, None),
    ],
)
def test_starts_task_with_client_token(
    ecs: Stubber, headers: dict[str, str] | None, client_token: str | None
) -> None:
    expected = dict(RUN_TASK_REQUEST)
    if client_token:
        expected["clientToken"] = client_token
    ecs.add_response("run_task", STARTED, expected)

    status, body = call_handler(headers)

    assert (status, body["status"], body["tasks"]) == (200, "started", ["arn:aws:ecs:task/1"])


def test_placement_failure_returns_503(ecs: Stubber) -> None:
    failures = [{"reason": "Capacity is unavailable at this time"}]
    ecs.add_response("run_task", {"tasks": [], "failures": failures})

    status, body = call_handler({"Idempotency-Key": "task-1"})

    assert (status, body["failures"]) == (503, failures)


def test_conflicting_client_token_is_a_duplicate(ecs: Stubber) -> None:
    ecs.add_client_error("run_task", service_error_code="ConflictException")

    status, body = call_handler({"Idempotency-Key": "task-1"})

    assert (status, body["status"]) == (200, "duplicate")


def test_ecs_error_propagates(ecs: Stubber) -> None:
    ecs.add_client_error("run_task", service_error_code="ServerException", http_status_code=500)

    with pytest.raises(botocore.exceptions.ClientError):
        call_handler({"Idempotency-Key": "task-1"})
