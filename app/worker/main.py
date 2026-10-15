import logging
import os
import signal
import threading
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from event_schema import NetworkEvent


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("atlasops.worker")
stop_requested = threading.Event()


def request_shutdown(signum, frame):
    logger.info("shutdown_requested signal=%s", signum)
    stop_requested.set()


def store_event(table, event):
    item = event.model_dump(mode="json")
    item["processed_at"] = datetime.now(timezone.utc).isoformat()

    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(event_id)",
        )
        return "stored"
    except ClientError as error:
        if (
            error.response["Error"]["Code"]
            == "ConditionalCheckFailedException"
        ):
            return "duplicate"
        raise

def notify_if_needed(table, sns, topic_arn, event_id):
    response = table.get_item(
        Key={"event_id": event_id},
        ConsistentRead=True,
    )
    item = response.get("Item")

    if item is None:
        raise RuntimeError(f"Stored event not found: {event_id}")

    if item["severity"] != "critical":
        return "not_required"

    if item.get("notification_status") == "published":
        return "already_published"

    message = (
        "AtlasOps critical network event\n\n"
        f"Event ID: {item['event_id']}\n"
        f"Device: {item['device_id']}\n"
        f"Event type: {item['event_type']}\n"
        f"Severity: {item['severity']}\n"
        f"Occurred at: {item['timestamp']}\n"
        f"Message: {item['message']}\n"
    )

    result = sns.publish(
        TopicArn=topic_arn,
        Subject="AtlasOps: critical network event",
        Message=message,
    )

    table.update_item(
        Key={"event_id": event_id},
        UpdateExpression=(
            "SET notification_status = :status, "
            "notification_published_at = :published_at, "
            "notification_message_id = :message_id"
        ),
        ConditionExpression="attribute_exists(event_id)",
        ExpressionAttributeValues={
            ":status": "published",
            ":published_at": datetime.now(timezone.utc).isoformat(),
            ":message_id": result["MessageId"],
        },
    )

    return "published"

def main():
    queue_url = os.environ["SQS_QUEUE_URL"]
    table_name = os.environ["DYNAMODB_TABLE_NAME"]
    region = os.getenv("AWS_REGION", "us-east-1")
    topic_arn = os.environ["SNS_TOPIC_ARN"]

    signal.signal(signal.SIGTERM, request_shutdown)
    signal.signal(signal.SIGINT, request_shutdown)

    session = boto3.Session(region_name=region)

    sns = session.client(
        "sns",
        config=Config(
            connect_timeout=3,
            read_timeout=5,
            retries={"mode": "standard", "total_max_attempts": 2},
        ),
    )
    sqs = session.client(
        "sqs",
        config=Config(
            connect_timeout=3,
            read_timeout=25,
            retries={"mode": "standard", "total_max_attempts": 2},
        ),
    )
    table = session.resource(
        "dynamodb",
        config=Config(
            connect_timeout=3,
            read_timeout=5,
            retries={"mode": "standard", "total_max_attempts": 3},
        ),
    ).Table(table_name)

    logger.info("worker_started table=%s", table_name)

    while not stop_requested.is_set():
        try:
            response = sqs.receive_message(
                QueueUrl=queue_url,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20,
                VisibilityTimeout=60,
            )
        except Exception:
            logger.exception("queue_receive_failed")
            stop_requested.wait(5)
            continue

        for message in response.get("Messages", []):
            try:
                event = NetworkEvent.model_validate_json(message["Body"])
                outcome = store_event(table, event)

                notification = notify_if_needed(
                    table,
                    sns,
                    topic_arn,
                    event.event_id,
                )

                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )

                logger.info(
                    "event_processed event_id=%s outcome=%s notification=%s",
                    event.event_id,
                    outcome,
                    notification,
                )
            except Exception:
                logger.exception(
                    "event_processing_failed message_id=%s",
                    message.get("MessageId"),
                )
                stop_requested.wait(2)

    logger.info("worker_stopped")


if __name__ == "__main__":
    main()