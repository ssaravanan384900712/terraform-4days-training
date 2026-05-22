import json


def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Hello from robochef.co Lambda!",
            "owner": "saravanans",
            "path": event.get("rawPath", "/")
        })
    }
