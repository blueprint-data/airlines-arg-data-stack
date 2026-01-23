"""Generate signed URLs manifest for public JSON exports."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone

from google.cloud import storage
from google.oauth2 import service_account

DEFAULT_OBJECTS = {
    "headline": "prod/exports/headline.json",
    "airline_breakdown": "prod/exports/airline_breakdown.json",
    "tops": "prod/exports/tops.json",
    "bucket_distribution": "prod/exports/bucket_distribution.json",
    "daily_status": "prod/exports/daily_status.json",
}


def load_object_map() -> dict[str, str]:
    """Load the object map from env or defaults."""
    raw_map = os.getenv("SIGNED_OBJECT_MAP")
    if raw_map:
        parsed = json.loads(raw_map)
        if not isinstance(parsed, dict):
            raise ValueError("SIGNED_OBJECT_MAP must be a JSON object")
        return {str(key): str(value) for key, value in parsed.items()}
    return DEFAULT_OBJECTS


def build_credentials() -> service_account.Credentials | None:
    """Build service account credentials for signing."""
    key_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    if not key_path:
        return None
    return service_account.Credentials.from_service_account_file(key_path)


def main() -> None:
    bucket_name = os.getenv("SIGNED_GCS_BUCKET_NAME") or os.getenv(
        "EXPORT_GCS_BUCKET_NAME"
    )
    bucket_name = bucket_name or os.getenv("GCS_BUCKET_NAME")
    manifest_path = os.getenv("SIGNED_MANIFEST_PATH") or "prod/exports/manifest.json"
    expiration_days = int(os.getenv("SIGNED_URL_EXPIRATION_DAYS") or "7")

    if not bucket_name:
        raise ValueError("Missing SIGNED_GCS_BUCKET_NAME or EXPORT_GCS_BUCKET_NAME")

    credentials = build_credentials()
    client = storage.Client(credentials=credentials)
    bucket = client.bucket(bucket_name)
    object_map = load_object_map()

    generated_at = datetime.now(timezone.utc)
    expires_at = generated_at + timedelta(days=expiration_days)

    urls: dict[str, str] = {}
    for name, object_path in object_map.items():
        blob = bucket.blob(object_path)
        url = blob.generate_signed_url(
            expiration=expires_at,
            method="GET",
            version="v4",
            credentials=credentials,
        )
        urls[name] = url

    manifest = {
        "generated_at": generated_at.isoformat(),
        "expires_at": expires_at.isoformat(),
        "expiration_days": expiration_days,
        "bucket": bucket_name,
        "objects": object_map,
        "urls": urls,
    }

    manifest_blob = bucket.blob(manifest_path)
    manifest_blob.upload_from_string(
        json.dumps(manifest, indent=2),
        content_type="application/json",
    )

    print("Signed manifest uploaded.")
    print(f"  gs://{bucket_name}/{manifest_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Failed to generate signed manifest: {exc}", file=sys.stderr)
        sys.exit(1)
