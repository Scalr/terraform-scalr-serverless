import os

# The handler creates its boto3 client at import time; botocore Stubber replaces every call.
os.environ.update(
    AWS_DEFAULT_REGION="us-east-1",
    AWS_ACCESS_KEY_ID="testing",
    AWS_SECRET_ACCESS_KEY="testing",
    CLUSTER="cluster",
    TASK_DEFINITION="task-definition",
    SUBNET_IDS="subnet-a,subnet-b",
    SECURITY_GROUP="sg",
)
