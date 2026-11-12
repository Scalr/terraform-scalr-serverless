import base64
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
    "overrides": {},
}
TASK_ARN = "arn:aws:ecs:us-east-1:123456789012:task/cluster/1"


@pytest.fixture
def ecs() -> Iterator[Stubber]:
    with Stubber(lambda_function.ECS) as stubber:
        yield stubber
        stubber.assert_no_pending_responses()


def call_handler(headers: dict[str, str] | None, **event: object) -> tuple[int, dict]:
    response = lambda_function.lambda_handler({"headers": headers, **event}, None)
    assert response["headers"]["Scalr-Launcher-Version"] == lambda_function.LAUNCHER_VERSION
    return response["statusCode"], json.loads(response["body"])


@pytest.mark.parametrize("header_name", ["Idempotency-Key", "idempotency-key", "IDEMPOTENCY-KEY"])
def test_starts_agent_without_options_when_webhook_has_none(ecs: Stubber, header_name: str) -> None:
    ecs.add_response(
        "run_task", {"tasks": [{"taskArn": TASK_ARN}], "failures": []}, RUN_TASK_REQUEST
    )

    assert call_handler({header_name: "task-1"}) == (202, {"taskArn": TASK_ARN})


@pytest.mark.parametrize("is_base64", [False, True])
def test_sets_agent_options_from_webhook(ecs: Stubber, is_base64: bool) -> None:
    body = json.dumps(
        {
            "task_id": "atask-1",
            "agent_environment": {
                "SCALR_AGENT_TASK_ID": "atask-1",
                "SCALR_AGENT_TOKEN": "other-pool-token",
                "SCALR_AGENT_SINGLE": "false",
                "SCALR_URL": "https://example.com",
                "SCALR_AGENT_DEBUG": True,
            },
        }
    )
    if is_base64:
        body = base64.b64encode(body.encode()).decode()
    ecs.add_response(
        "run_task",
        {"tasks": [{"taskArn": TASK_ARN}], "failures": []},
        {
            **RUN_TASK_REQUEST,
            "overrides": {
                "containerOverrides": [
                    {
                        "name": "scalr-agent",
                        "environment": [{"name": "SCALR_AGENT_TASK_ID", "value": "atask-1"}],
                    }
                ]
            },
        },
    )

    assert call_handler({"Idempotency-Key": "task-1"}, body=body, isBase64Encoded=is_base64) == (
        202,
        {"taskArn": TASK_ARN},
    )


@pytest.mark.parametrize("body", ["not json", "[]", '{"agent_environment": []}'])
def test_ignores_malformed_webhook_body(ecs: Stubber, body: str) -> None:
    ecs.add_response(
        "run_task", {"tasks": [{"taskArn": TASK_ARN}], "failures": []}, RUN_TASK_REQUEST
    )

    assert call_handler({"Idempotency-Key": "task-1"}, body=body) == (202, {"taskArn": TASK_ARN})


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
