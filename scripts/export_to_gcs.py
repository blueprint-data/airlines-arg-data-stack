"""Export BigQuery data to Google Cloud Storage as JSON."""

from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime
from decimal import Decimal

from google.cloud import bigquery, storage

DEFAULT_EXPORTS = {
    "public_headline": "headline.json",
    "public_airline_breakdown": "airline_breakdown.json",
    "public_tops": "tops.json",
    "public_bucket_distribution": "bucket_distribution.json",
    "public_daily_status": "daily_status.json",
    "public_gates_analysis": "gates_analysis.json",
    "routes_metrics": "routes_metrics.json",
}


def serialize_value(value: object) -> str | float:
    """Convert non-JSON types to serializable values."""
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return str(value)


def resolve_export_prefix(blob_path: str | None) -> str:
    """Resolve export prefix from blob path or env var."""
    prefix = os.getenv("EXPORT_GCS_PREFIX")
    if prefix:
        return prefix.strip().strip("/")
    if blob_path and "/" in blob_path:
        return blob_path.rsplit("/", 1)[0]
    return "data"


def resolve_exports(prefix: str) -> dict[str, str]:
    """Resolve table-to-blob mappings for export."""
    table_map = os.getenv("EXPORT_TABLE_MAP")
    if table_map:
        parsed = json.loads(table_map)
        if not isinstance(parsed, dict):
            raise ValueError(
                "EXPORT_TABLE_MAP must be a JSON object mapping table -> path"
            )
        resolved = {}
        for table_name, path in parsed.items():
            if not isinstance(path, str):
                raise ValueError("EXPORT_TABLE_MAP values must be strings")
            resolved[table_name] = path if "/" in path else f"{prefix}/{path}"
        return resolved

    tables = os.getenv("EXPORT_TABLES")
    if tables:
        return {
            table.strip(): f"{prefix}/{table.strip()}.json"
            for table in tables.split(",")
            if table.strip()
        }

    return {
        table: f"{prefix}/{filename}" for table, filename in DEFAULT_EXPORTS.items()
    }


def resolve_raw_tables() -> set[str]:
    """Resolve tables that should be exported as raw JSON arrays."""
    raw_tables = os.getenv("EXPORT_RAW_TABLES")
    if not raw_tables:
        return set()
    return {table.strip() for table in raw_tables.split(",") if table.strip()}


def build_query(project_id: str, dataset_id: str, table_id: str) -> str:
    """Build a query for exporting a table."""
    return f"SELECT * FROM `{project_id}.{dataset_id}.{table_id}`"


def export_table(
    bq_client: bigquery.Client,
    storage_client: storage.Client,
    project_id: str,
    dataset_id: str,
    table_id: str,
    bucket_name: str,
    blob_path: str,
    raw: bool = False,
) -> str | None:
    """Export a single table to GCS."""
    query = build_query(project_id, dataset_id, table_id)

    print(f"Executing query for {table_id}...")
    query_job = bq_client.query(query)
    results = query_job.result()

    data = [dict(row) for row in results]
    print(f"Rows fetched ({table_id}): {len(data)}")

    if not data:
        print(f"No data returned for {table_id}.")
        return None

    exported_at = datetime.utcnow().isoformat()
    if raw:
        payload = data
    else:
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

    print(f"Uploading {table_id} to gs://{bucket_name}/{blob_path}...")
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


def export_bigquery_to_gcs() -> dict[str, str | None]:
    """Extract data from BigQuery and upload it to GCS as JSON."""
    try:
        project_id = os.getenv("BIGQUERY_PROJECT_ID") or os.getenv("GCP_PROJECT_ID")
        dataset_id = (
            os.getenv("EXPORT_BQ_DATASET_ID")
            or os.getenv("BQ_DATASET_ID")
            or os.getenv("BIGQUERY_DATASET_ID")
            or "marts"
        )
        bucket_name = os.getenv("EXPORT_GCS_BUCKET_NAME") or os.getenv(
            "GCS_BUCKET_NAME"
        )
        blob_path = os.getenv("EXPORT_GCS_BLOB_PATH") or os.getenv("GCS_BLOB_PATH")

        if not project_id or not bucket_name:
            raise ValueError(
                "Missing required env vars: BIGQUERY_PROJECT_ID (or GCP_PROJECT_ID), "
                "EXPORT_GCS_BUCKET_NAME (or GCS_BUCKET_NAME)."
            )

        prefix = resolve_export_prefix(blob_path)
        exports = resolve_exports(prefix)
        raw_tables = resolve_raw_tables()

        print("Config:")
        print(f"  Project: {project_id}")
        print(f"  Dataset: {dataset_id}")
        print(f"  Bucket: {bucket_name}")
        print(f"  Export prefix: {prefix}")
        print("  Tables:")
        for table_name, path in exports.items():
            print(f"    - {table_name} -> {path}")

        bq_client = bigquery.Client(project=project_id)
        storage_client = storage.Client(project=project_id)

        results = {}
        for table_name, path in exports.items():
            results[table_name] = export_table(
                bq_client,
                storage_client,
                project_id,
                dataset_id,
                table_name,
                bucket_name,
                path,
                raw=table_name in raw_tables,
            )

        return results
    except Exception as exc:
        print(f"Export failed: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    export_bigquery_to_gcs()
