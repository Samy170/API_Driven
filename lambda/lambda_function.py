import os
import json
import boto3

def handler(event, context):
    endpoint = os.environ["AWS_ENDPOINT_URL"]
    instance_id = os.environ["INSTANCE_ID"]
    region = os.environ.get("AWS_REGION", "us-east-1")

    ec2 = boto3.client(
        "ec2",
        endpoint_url=endpoint,
        region_name=region
    )

    qs = event.get("queryStringParameters") or {}
    action = (qs.get("action") or "").lower().strip()

    if action == "start":
        ec2.start_instances(InstanceIds=[instance_id])
        result = {
            "action": "start",
            "instance": instance_id
        }

    elif action == "stop":
        ec2.stop_instances(InstanceIds=[instance_id])
        result = {
            "action": "stop",
            "instance": instance_id
        }

    elif action == "status":
        response = ec2.describe_instances(InstanceIds=[instance_id])
        state = response["Reservations"][0]["Instances"][0]["State"]["Name"]
        result = {
            "instance": instance_id,
            "state": state
        }

    else:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Use ?action=start | stop | status"})
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(result)
    }
