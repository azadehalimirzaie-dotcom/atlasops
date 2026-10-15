import logging
import os
from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException

from event_schema import NetworkEvent


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("atlasops.ingestion")

app = FastAPI(title="AtlasOps Ingestion API", version="0.1.0")


@lru_cache
def sqs_client():
    return boto3.client(
        "sqs",
        region_name=os.getenv("AWS_REGION", "us-east-1"),
        config=Config(
            connect_timeout=3,
            read_timeout=5,
            retries={"mode": "standard", "total_max_attempts": 3},
        ),
    )


@app.get("/health")
def health():
    # Process health only; does not check AWS connectivity.
    return {"status": "ok", "service": "ingestion"}


@app.post("/events", status_code=202)
def submit_event(event: NetworkEvent):
    queue_url = os.getenv("SQS_QUEUE_URL")
    if not queue_url:
        raise HTTPException(
            status_code=503,
            detail="Event queue is not configured",
        )

    try:
        response = sqs_client().send_message(
            QueueUrl=queue_url,
            MessageBody=event.model_dump_json(),
        )
    except (BotoCoreError, ClientError):
        logger.exception("queue_send_failed event_id=%s", event.event_id)
        raise HTTPException(
            status_code=503,
            detail="Unable to queue event; retry using the same event_id",
        ) from None

    logger.info(
        "event_accepted event_id=%s message_id=%s",
        event.event_id,
        response["MessageId"],
    )

    return {
        "status": "accepted",
        "event_id": event.event_id,
        "message_id": response["MessageId"],
    }