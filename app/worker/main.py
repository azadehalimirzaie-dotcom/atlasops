import logging
import os
import signal
import threading
from datetime import datetime, timezone
from time import perf_counter

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from event_schema import NetworkEvent
from prometheus_client import Counter, Histogram, start_http_server

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("atlasops.worker")
stop_requested = threading.Event()

STORAGE_RESULTS = Counter(
    "atlasops_worker_storage_results_total",
    "Completed DynamoDB storage checks",
    ["outcome"],
)

NOTIFICATION_RESULTS = Counter(
    "atlasops_worker_notification_results_total",
    "Completed notification handling operations",
    ["outcome"],
)

PROCESSING_ATTEMPTS = Counter(
    "atlasops_worker_processing_attempts_total",
    "Message processing attempts, including SQS retries",
    ["outcome"],
)

PROCESSING_FAILURES = Counter(
    "atlasops_worker_processing_failures_total",
    "Failed message processing attempts by stage",
    ["stage"],
)

PROCESSING_DURATION = Histogram(
    "atlasops_worker_processing_duration_seconds",
    "Message processing time, excluding queue polling and retry delay",
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60),
)

QUEUE_RECEIVE_FAILURES = Counter(
    "atlasops_worker_queue_receive_failures_total",
    "Failed SQS receive operations",
)

# Make known outcomes visible even before the first event arrives.
for outcome in ("stored", "duplicate"):
    STORAGE_RESULTS.labels(outcome=outcome)

for outcome in ("published", "already_published", "not_required"):
    NOTIFICATION_RESULTS.labels(outcome=outcome)

for outcome in ("success", "failed"):
    PROCESSING_ATTEMPTS.labels(outcome=outcome)

for stage in ("validation", "storage", "notification", "acknowledgement"):
    PROCESSING_FAILURES.labels(stage=stage)

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
            started_at = perf_counter()
            stage = "validation"
            failed = False

            try:
                event = NetworkEvent.model_validate_json(message["Body"])

                stage = "storage"
                outcome = store_event(table, event)
                STORAGE_RESULTS.labels(outcome=outcome).inc()

                stage = "notification"
                notification = notify_if_needed(
                    table,
                    sns,
                    topic_arn,
                    event.event_id,
                )
                NOTIFICATION_RESULTS.labels(outcome=notification).inc()

                stage = "acknowledgement"
                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )

            except Exception:
                failed = True
                PROCESSING_ATTEMPTS.labels(outcome="failed").inc()
                PROCESSING_FAILURES.labels(stage=stage).inc()

                logger.exception(
                    "event_processing_failed message_id=%s stage=%s",
                    message.get("MessageId"),
                    stage,
                )

            else:
                PROCESSING_ATTEMPTS.labels(outcome="success").inc()

                logger.info(
                    "event_processed event_id=%s outcome=%s notification=%s",
                    event.event_id,
                    outcome,
                    notification,
                )

            finally:
                PROCESSING_DURATION.observe(perf_counter() - started_at)

            if failed:
                # Leave the message on SQS for retry.
                stop_requested.wait(2)
        

    logger.info("worker_stopped")


if __name__ == "__main__":
    main()