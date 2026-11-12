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
def fetch_launches_page(url, params=None):
    response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.json()


def run_ingestion_pipeline():
    storage_client = storage.Client()
    bucket = storage_client.bucket(BUCKET_NAME)

    last_updated = load_state(bucket)
    print(f"Starting ingestion from watermark: {last_updated}")

    run_timestamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d_%H%M%S")
    url = BASE_URL
    params = {
        "limit": PAGE_SIZE,
        "mode": "detailed",
        "net__gte": START_DATE,
        "last_updated__gte": last_updated,
        "ordering": "last_updated",
    }
    offset = 0
    latest_updated = None

    while url:
        try:
            page_data = fetch_launches_page(url, params)
            params = None
            results = page_data.get("results", [])

            if not results or (
                results[-1]["last_updated"] == last_updated and not page_data.get("next")
            ):
                print("No new or updated launches found.")
                break

            save_raw_page(bucket, page_data, run_timestamp, offset)
            latest_updated = results[-1]["last_updated"]
            print(
                f"Saved {len(results)} records at offset {offset}. "
                f"Page watermark: {latest_updated}."
            )

            url = page_data.get("next")
            offset += PAGE_SIZE
        except requests.exceptions.RequestException as e:
            print(f"HTTP/Network error at offset {offset}: {e}")
            raise

    if latest_updated and latest_updated != last_updated:
        save_state(bucket, latest_updated)
        print(f"Ingestion complete. Updated watermark to {latest_updated}.")


if __name__ == "__main__":
    run_ingestion_pipeline()
