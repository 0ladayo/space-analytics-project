import datetime
import json
import os

import requests
from google.cloud import storage
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

BASE_URL = os.getenv(
    "API_BASE_URL",
    "https://lldev.thespacedevs.com/2.3.0/launches/previous/",
)
START_DATE = os.getenv("START_DATE", "2026-01-01T00:00:00Z")
BUCKET_NAME = os.environ["RAW_BUCKET_NAME"]
STATE_BLOB_NAME = "state/state.json"
PAGE_SIZE = 50
REQUEST_TIMEOUT = (5, 60)


def load_state(bucket):
    blob = bucket.blob(STATE_BLOB_NAME)
    if blob.exists():
        state_data = json.loads(blob.download_as_text())
        return state_data["last_updated"]
    return START_DATE


def save_state(bucket, last_updated):
    blob = bucket.blob(STATE_BLOB_NAME)
    blob.upload_from_string(
        json.dumps({"last_updated": last_updated}),
        content_type="application/json",
    )


def save_raw_page(bucket, page_data, run_timestamp, offset):
    blob_name = f"launches/raw_launches_{run_timestamp}_offset_{offset}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(page_data),
        content_type="application/json",
    )


@retry(
    stop=stop_after_attempt(4),
    wait=wait_exponential(multiplier=2, min=2, max=30),
    retry=retry_if_exception_type(
        (requests.exceptions.Timeout, requests.exceptions.ConnectionError)
    ),
    reraise=True,
)
def fetch_launches_page(last_updated, next_url=None):
    if next_url:
        response = requests.get(next_url, timeout=REQUEST_TIMEOUT)
    else:
        query_params = {
            "limit": PAGE_SIZE,
            "mode": "detailed",
            "net__gte": START_DATE,
            "last_updated__gte": last_updated,
            "ordering": "last_updated",
        }
        response = requests.get(BASE_URL, params=query_params, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.json()


def run_ingestion_pipeline():
    storage_client = storage.Client()
    bucket = storage_client.bucket(BUCKET_NAME)

    last_updated = load_state(bucket)
    print(f"Starting ingestion from watermark: {last_updated}")

    run_timestamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d_%H%M%S")
    next_url = None
    offset = 0
    has_more_data = True

    while has_more_data:
        try:
            page_data = fetch_launches_page(last_updated, next_url)
            results = page_data.get("results", [])
            if not results:
                print("No new or updated launches found.")
                break

            save_raw_page(bucket, page_data, run_timestamp, offset)
            latest_updated = results[-1]["last_updated"]
            save_state(bucket, latest_updated)
            print(
                f"Saved {len(results)} records at offset {offset}. "
                f"Updated watermark to {latest_updated}."
            )

            next_url = page_data.get("next")
            if next_url is None:
                has_more_data = False
            else:
                offset += PAGE_SIZE
        except requests.exceptions.RequestException as e:
            print(f"HTTP/Network error at offset {offset}: {e}")
            raise


if __name__ == "__main__":
    run_ingestion_pipeline()
