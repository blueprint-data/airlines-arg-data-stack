"""Export BigQuery data to Google Cloud Storage as JSON."""

from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime
from decimal import Decimal

from google.cloud import bigquery, storage


def serialize_value(value: object) -> str | float:
    """Convert non-JSON types to serializable values."""
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return str(value)


def export_bigquery_to_gcs() -> str | None:
    """Extract data from BigQuery and upload it to GCS as JSON."""
    try:
        project_id = os.getenv("BIGQUERY_PROJECT_ID") or os.getenv("GCP_PROJECT_ID")
        dataset_id = (
            os.getenv("EXPORT_BQ_DATASET_ID")
            or os.getenv("BQ_DATASET_ID")
            or os.getenv("BIGQUERY_DATASET_ID")
            or "marts"
        )
        table_id = (
            os.getenv("EXPORT_BQ_TABLE_ID")
            or os.getenv("BQ_TABLE_ID")
            or "flights_performance"
        )
        bucket_name = os.getenv("EXPORT_GCS_BUCKET_NAME") or os.getenv(
            "GCS_BUCKET_NAME"
        )
        blob_path = (
            os.getenv("EXPORT_GCS_BLOB_PATH")
            or os.getenv("GCS_BLOB_PATH")
            or f"data/{table_id}.json"
        )
        date_column = os.getenv("EXPORT_BQ_DATE_COLUMN") or "flight_date"
        lookback_days = int(os.getenv("EXPORT_BQ_LOOKBACK_DAYS") or "30")
        limit = int(os.getenv("EXPORT_BQ_LIMIT") or "10000")

        if not project_id or not bucket_name:
            raise ValueError(
                "Missing required env vars: BIGQUERY_PROJECT_ID (or GCP_PROJECT_ID), "
                "EXPORT_GCS_BUCKET_NAME (or GCS_BUCKET_NAME)."
            )

        print("Config:")
        print(f"  Project: {project_id}")
        print(f"  Dataset: {dataset_id}")
        print(f"  Table: {table_id}")
        print(f"  Date column: {date_column}")
        print(f"  Lookback days: {lookback_days}")
        print(f"  Limit: {limit}")
        print(f"  Destination: gs://{bucket_name}/{blob_path}")

        bq_client = bigquery.Client(project=project_id)
        storage_client = storage.Client(project=project_id)

        query = f"""
            SELECT *
            FROM `{project_id}.{dataset_id}.{table_id}`
            WHERE DATE({date_column}) >= DATE_SUB(CURRENT_DATE(), INTERVAL {lookback_days} DAY)
            ORDER BY {date_column} DESC
            LIMIT {limit}
        """

        print("Executing BigQuery query...")
        query_job = bq_client.query(query)
        results = query_job.result()

        data = [dict(row) for row in results]
        print(f"Rows fetched: {len(data)}")

        if not data:
            print("No data returned from BigQuery.")
            return None

        exported_at = datetime.utcnow().isoformat()
        payload = {
            "metadata": {
                "exported_at": exported_at,
                "source": f"{project_id}.{dataset_id}.{table_id}",
                "total_records": len(data),
            },
            "data": data,
        }

        json_data = json.dumps(
            payload,
            default=serialize_value,
            ensure_ascii=False,
            indent=2,
        )

        print("Uploading to GCS...")
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_path)
        blob.upload_from_string(json_data, content_type="application/json")
        blob.metadata = {
            "exported_at": exported_at,
            "record_count": str(len(data)),
        }
        blob.patch()

        gcs_url = f"gs://{bucket_name}/{blob_path}"
        public_url = f"https://storage.googleapis.com/{bucket_name}/{blob_path}"

        print("Export completed.")
        print(f"  GCS URI: {gcs_url}")
        print(f"  Public URL: {public_url}")
        print(f"  Payload size: {len(json_data) / 1024:.2f} KB")

        return gcs_url
    except Exception as exc:
        print(f"Export failed: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    export_bigquery_to_gcs()
