import datetime
import json
import os

import functions_framework
from google.cloud import bigquery, storage

PREFIX = os.getenv("PREFIX_NAME", "launches/")
TRIGGER_BLOB_NAME = os.getenv("TRIGGER_BLOB_NAME", "state/state.json")
STATE_BLOB_NAME = os.getenv("LOADER_STATE_BLOB_NAME", "state/loading_state.json")
TABLE_ID = os.environ["BIGQUERY_TABLE_ID"]

storage_client = storage.Client()
bq_client = bigquery.Client()


def load_state(bucket):
    blob = bucket.blob(STATE_BLOB_NAME)
    if blob.exists():
        state_data = json.loads(blob.download_as_text())
        raw_time = state_data.get("last_processed_time")
        return datetime.datetime.fromisoformat(raw_time) if raw_time else None
    return None


def save_state(bucket, last_processed_time):
    blob = bucket.blob(STATE_BLOB_NAME)
    blob.upload_from_string(
        json.dumps({"last_processed_time": last_processed_time.isoformat()}),
        content_type="application/json",
    )


def get_new_blobs(bucket, last_processed_time):
    blobs = bucket.list_blobs(prefix=PREFIX)
    return [
        blob
        for blob in blobs
        if blob.name.endswith(".json")
        and blob.time_created is not None
        and (last_processed_time is None or blob.time_created > last_processed_time)
    ]


def extract_fields(item):
    status = item.get("status") or {}
    agency = item.get("launch_service_provider") or {}
    countries = agency.get("country") or [{}]
    rocket = item.get("rocket") or {}
    mission = item.get("mission") or {}
    orbit = mission.get("orbit") or {}
    pad = item.get("pad") or {}

    fields = [
        ("launch_id", "STRING", item.get("id")),
        ("launch_name", "STRING", item.get("name")),
        ("last_updated", "TIMESTAMP", item.get("last_updated")),
        ("net", "TIMESTAMP", item.get("net")),
        ("window_start", "TIMESTAMP", item.get("window_start")),
        ("window_end", "TIMESTAMP", item.get("window_end")),
        ("status_name", "STRING", status.get("name")),
        ("status_abbrev", "STRING", status.get("abbrev")),
        ("fail_reason", "STRING", item.get("failreason")),
        ("agency_id", "INT64", agency.get("id")),
        ("agency_name", "STRING", agency.get("name")),
        ("agency_type", "STRING", (agency.get("type") or {}).get("name")),
        ("agency_country", "STRING", countries[0].get("alpha_3_code")),
        ("rocket_id", "INT64", rocket.get("id")),
        ("rocket_name", "STRING", (rocket.get("configuration") or {}).get("full_name")),
        ("mission_name", "STRING", mission.get("name")),
        ("mission_type", "STRING", mission.get("type")),
        ("orbit_name", "STRING", orbit.get("name")),
        ("orbit_abbrev", "STRING", orbit.get("abbrev")),
        ("pad_id", "INT64", pad.get("id")),
        ("pad_name", "STRING", pad.get("name")),
        ("location_name", "STRING", (pad.get("location") or {}).get("name")),
        ("latitude", "FLOAT64", pad.get("latitude")),
        ("longitude", "FLOAT64", pad.get("longitude")),
        ("pad_total_launches", "INT64", pad.get("total_launch_count")),
    ]
    return bigquery.StructQueryParameter(
        None,
        *(bigquery.ScalarQueryParameter(col, dtype, val) for col, dtype, val in fields),
    )


@functions_framework.cloud_event
def load_launches(cloud_event):
    if cloud_event.data["name"] != TRIGGER_BLOB_NAME:
        return

    bucket = storage_client.bucket(cloud_event.data["bucket"])
    last_processed_time = load_state(bucket)

    new_blobs = get_new_blobs(bucket, last_processed_time)
    if not new_blobs:
        print("No new raw files to load.")
        return

    structs = []
    for blob in new_blobs:
        results = json.loads(blob.download_as_text()).get("results", [])
        for item in results:
            structs.append(extract_fields(item))

    if structs:
        update_set = ", ".join(f"{col} = S.{col}" for col in structs[0].struct_types)
        merge_query = f"""
        MERGE `{TABLE_ID}` T
        USING (
          SELECT *
          FROM UNNEST(@rows)
          QUALIFY ROW_NUMBER() OVER (PARTITION BY launch_id ORDER BY last_updated DESC) = 1
        ) S
        ON T.launch_id = S.launch_id
        WHEN MATCHED AND S.last_updated > T.last_updated THEN
          UPDATE SET {update_set}
        WHEN NOT MATCHED THEN
          INSERT ROW
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ArrayQueryParameter("rows", "STRUCT", structs)]
        )
        job = bq_client.query(merge_query, job_config=job_config)
        job.result()
        print(f"Merged {job.num_dml_affected_rows} rows from {len(new_blobs)} file(s).")

    latest_blob_time = max(blob.time_created for blob in new_blobs)
    save_state(bucket, latest_blob_time)
    print(f"Updated loader watermark to {latest_blob_time.isoformat()}.")
