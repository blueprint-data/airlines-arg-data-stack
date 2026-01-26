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
    "gates_analysis": "prod/exports/gates_analysis.json",
    "routes_metrics": "prod/exports/routes_metrics.json",
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
    output_path = os.getenv("SIGNED_MANIFEST_URL_OUTPUT")
    log_url = (os.getenv("SIGNED_MANIFEST_LOG_URL") or "true").strip().lower()
    public_manifest = (
        os.getenv("SIGNED_MANIFEST_PUBLIC") or "false"
    ).strip().lower() in {"1", "true", "yes"}

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

    if public_manifest:
        try:
            manifest_blob.make_public()
        except Exception as exc:
            raise RuntimeError(
                "Failed to make manifest public. If your bucket enforces uniform "
                "bucket-level access, grant allUsers the Storage Object Viewer role "
                "on the bucket or use a separate public bucket for the manifest."
            ) from exc

    manifest_url = manifest_blob.generate_signed_url(
        expiration=expires_at,
        method="GET",
        version="v4",
        credentials=credentials,
    )

    print("Signed manifest uploaded.")
    print(f"  gs://{bucket_name}/{manifest_path}")
    if public_manifest:
        print("Public manifest URL:")
        print(f"  {manifest_blob.public_url}")
    if log_url not in {"0", "false", "no"}:
        print("Signed manifest URL:")
        print(f"  {manifest_url}")

    if output_path:
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(f"{manifest_url}\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Failed to generate signed manifest: {exc}", file=sys.stderr)
        sys.exit(1)
