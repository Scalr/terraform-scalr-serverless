import hashlib
import json
from collections.abc import Iterator

import pytest
from botocore.stub import Stubber

import lambda_function

RUN_TASK_REQUEST = {
    "cluster": "cluster",
    "taskDefinition": "task-definition",
    "launchType": "FARGATE",
    "count": 1,
    "clientToken": hashlib.sha256(b"task-1").hexdigest(),
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": ["subnet-a", "subnet-b"],
            "securityGroups": ["sg"],
            "assignPublicIp": "ENABLED",
        }
    },
}
TASK_ARN = "arn:aws:ecs:us-east-1:123456789012:task/cluster/1"


@pytest.fixture
def ecs() -> Iterator[Stubber]:
    with Stubber(lambda_function.ECS) as stubber:
        yield stubber
        stubber.assert_no_pending_responses()


def call_handler(headers: dict[str, str] | None) -> tuple[int, dict]:
    response = lambda_function.lambda_handler({"headers": headers}, None)
    return response["statusCode"], json.loads(response["body"])


@pytest.mark.parametrize("header_name", ["Idempotency-Key", "idempotency-key", "IDEMPOTENCY-KEY"])
def test_requests_task_with_hashed_client_token(ecs: Stubber, header_name: str) -> None:
    ecs.add_response(
        "run_task", {"tasks": [{"taskArn": TASK_ARN}], "failures": []}, RUN_TASK_REQUEST
    )

    assert call_handler({header_name: "task-1"}) == (202, {"taskArn": TASK_ARN})


@pytest.mark.parametrize("headers", [None, {}, {"Idempotency-Key": ""}])
def test_rejects_request_without_idempotency_key(
    ecs: Stubber, headers: dict[str, str] | None
) -> None:
    assert call_handler(headers) == (400, {"error": "Idempotency-Key header is required"})


def test_launch_failure_returns_502(ecs: Stubber) -> None:
    ecs.add_response("run_task", {"tasks": [], "failures": [{"reason": "RESOURCE:MEMORY"}]})

    assert call_handler({"Idempotency-Key": "task-1"}) == (
        502,
        {"error": "ECS could not launch the task"},
    )


@pytest.mark.parametrize("error_code", ["ConflictException", "ServerException"])
def test_ecs_error_returns_502(ecs: Stubber, error_code: str) -> None:
    ecs.add_client_error("run_task", service_error_code=error_code)

    assert call_handler({"Idempotency-Key": "task-1"}) == (
        502,
        {"error": "ECS RunTask request failed"},
    )
