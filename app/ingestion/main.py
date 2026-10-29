import logging
import os
from functools import lru_cache
from time import perf_counter

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, make_asgi_app

from event_schema import NetworkEvent
from fastapi import Request


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("atlasops.ingestion")

app = FastAPI(title="AtlasOps Ingestion API", version="0.1.0")
EVENT_REQUESTS = Counter(
    "atlasops_ingestion_requests_total",
    "HTTP requests to POST /events, including validation failures",
    ["status_code"],
)

EVENT_REQUEST_DURATION = Histogram(
    "atlasops_ingestion_request_duration_seconds",
    "Time to handle POST /events",
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60),
)

EVENTS_QUEUED = Counter(
    "atlasops_ingestion_events_queued_total",
    "Events successfully submitted to SQS",
)

QUEUE_FAILURES = Counter(
    "atlasops_ingestion_queue_failures_total",
    "Event submissions that failed during the SQS send operation",
)

# Prometheus reads this endpoint; no additional port is needed.
app.mount("/metrics", make_asgi_app())


@app.middleware("http")
async def record_event_request_metrics(request: Request, call_next):
    # Exclude health checks and Prometheus scrapes from event metrics.
    if request.method != "POST" or request.url.path != "/events":
        return await call_next(request)

    started_at = perf_counter()
    status_code = 500

    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        EVENT_REQUESTS.labels(status_code=str(status_code)).inc()
        EVENT_REQUEST_DURATION.observe(perf_counter() - started_at)


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
        QUEUE_FAILURES.inc()
        logger.exception("queue_send_failed event_id=%s", event.event_id)
        raise HTTPException(
            status_code=503,
            detail="Unable to queue event; retry using the same event_id",
        ) from None
    
    
    EVENTS_QUEUED.inc()

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