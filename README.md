# airlines-arg-data-stack

## What is this?

This template builds an end-to-end stack for Argentine aviation data: it extracts flight metadata from the Aeropuertos Argentina API, loads it into BigQuery, and transforms it with dbt. You do not need deep Meltano or dbt knowledge to follow along; the README walks through every step.

It is targeted at small teams or pilots of analytics stacks: fast to bootstrap, opinionated but readable, and with CI/CD ready for tests and docs.

## 🎯 Prerequisites (read first)

**Software required (install if missing)**

- Python 3.11+: https://www.python.org/downloads/
- Git: https://git-scm.com/downloads
- Google Cloud account (billing-enabled project or rights to create one): https://console.cloud.google.com/
- Optional but recommended: gcloud CLI https://cloud.google.com/sdk/docs/install

## What it includes

- Extraction with Meltano (`tap-airlines-arg` + `target-bigquery`)
- Transformation with dbt (staging -> marts)
- Models and columns documented in YAML
- CI/CD workflows and dbt docs on GitHub Pages

## Quick start (Happy Path)

If you do not have a Google Cloud account, create one. If you already have GCP, create a new project for this stack.

1. [IAM] Create service accounts

   In IAM & Admin:

   - Go to Service Accounts and create one account for dbt and one for Meltano
     (or reuse a single account for both).
   - For each service account, create a JSON key and download it.
   - Rename the files (for example): `dbt-service-account.json` and `meltano-service-account.json`.
   - Go back to IAM and grant access to each service account email
     (example: `meltano@data.iam.gserviceaccount.com`).
   - Assign the role `BigQuery Data Owner` (or the minimum you need for datasets/jobs).

2. [GCS] Create a GCS bucket for Meltano state

   In Cloud Storage -> Buckets:

   - Create a private bucket (example: `template-bigquery`).
   - Recommended settings:
     - Public access prevention: Enabled
     - Access control: Uniform
     - Storage class: Standard
     - Encryption: Google-managed

   Then in bucket permissions:

   - Add the Meltano service account (for example: `meltano@<project-id>.iam.gserviceaccount.com`).
   - Grant the role `Storage Object Admin`.

   This allows Meltano to create and manage state files.

3. [DB] Create BigQuery datasets (or grant create permissions)

   You will need datasets for raw and modeled data:

   - Raw: `${MELTANO_ENVIRONMENT}_${MELTANO_EXTRACTOR_NAMESPACE}`
     (defaults to `<env>_tap_airlines_arg` based on `extraction/meltano.yml`).
   - Modeled: `stg` and `marts` (prod/ci). For dev, dbt uses `SANDBOX_<DBT_USER>`.

4. [CFG] Configure variables

```bash
cd airlines-arg-data-stack
cp .env.example .env
```

Edit `.env` with your credentials. Minimal example:

```bash
BIGQUERY_PROJECT_ID=your-gcp-project
BIGQUERY_DATASET_ID=analytics
BIGQUERY_LOCATION=southamerica-east1
DBT_GOOGLE_APPLICATION_CREDENTIALS=/path/to/dbt-service-account.json
MELTANO_GOOGLE_APPLICATION_CREDENTIALS=/path/to/meltano-service-account.json
GOOGLE_APPLICATION_CREDENTIALS=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}
MELTANO_STATE_BACKEND_URI=gs://your-bucket/meltano/state

TARGET_BIGQUERY_PROJECT=${BIGQUERY_PROJECT_ID}
TARGET_BIGQUERY_LOCATION=${BIGQUERY_LOCATION}
TARGET_BIGQUERY_CREDENTIALS_PATH=${MELTANO_GOOGLE_APPLICATION_CREDENTIALS}

DBT_USER=local

# TAP_AIRLINES_DAYS_BACK=1  # Controls how many days of history the extractor requests (keep low for daily syncs)
```

> [i] INFO: If you prefer a single service account, set both credential paths to
> the same file.
> [i] INFO: `GOOGLE_APPLICATION_CREDENTIALS` should point to the Meltano account
> so the GCS state backend can write to your bucket.
> [!] WARNING: dbt sources read from `<target>_tap_airlines_arg`. Run Meltano in the
> same environment as the dbt target you plan to build.
> [i] INFO: The tap ships with defaults for API URL, API key, airports, origin,
> user-agent, and language. To override them, add the config keys under
> `tap-airlines-arg` in `extraction/meltano.yml` or set the matching
> `TAP_AIRLINES_*` environment variables.

Optional tap overrides (add to `.env` if you want to customize):

```bash
TAP_AIRLINES_API_URL=https://webaa-api-h4d5amdfcze7hthn.a02.azurefd.net/web-prod/v1/api-aa
TAP_AIRLINES_API_KEY=your-api-key-here
TAP_AIRLINES_AIRPORTS='["AEP","EZE","COR","MDZ"]'
TAP_AIRLINES_DAYS_BACK=1
TAP_AIRLINES_ORIGIN=https://www.aeropuertosargentina.com
TAP_AIRLINES_USER_AGENT=airlines-arg-data-stack/1.0
TAP_AIRLINES_LANGUAGE=es-AR
```

5. [LOCAL] Set up the extraction environment

```bash
cd extraction
./scripts/setup-local.sh
source venv/bin/activate
set -a; source ../.env; set +a
```

With the virtual environment active, you can optionally authenticate gcloud if you
prefer Application Default Credentials (instead of service-account JSONs):

```bash
gcloud auth application-default login
```

This creates the venv, installs Meltano dependencies, and initializes the project.

6. [TEST] Verify the state backend

From `extraction/` with the venv active:

```bash
set -a; source ../.env; set +a
meltano state list
```

Expected: no errors, and either an empty list or existing states.

7. [EXT] Run extraction once (Meltano)

```bash
set -a; source ../.env; set +a
meltano --environment=prod run tap-airlines-arg target-bigquery
```

> [!] WARNING: dbt sources point to `<target>_tap_airlines_arg` (for example `prod_tap_airlines_arg`).
> Run Meltano with the same environment as your dbt target.

8. [DBT] Run transform and build models

```bash
cd ../transform
./scripts/setup-local.sh
source venv/bin/activate
cp profiles.yml.example profiles.yml
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt deps
dbt build --target prod
```

> [i] INFO: `dbt build` runs models and tests, so it is used in PR/deploy.
> [i] INFO: Every time you change a model, run `dbt build` again (or a selective build).

9. [SQL] See results in the DB

```sql
select * from marts.flights_performance limit 10;
select * from marts.airline_metrics limit 10;
select airport_code, count(*) from marts.flights_performance group by airport_code order by airport_code;
```

10. [DOCS] Generate dbt docs (optional)

```bash
cd ../transform
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt docs generate --target prod
dbt docs serve --target prod
```

Opens at: http://localhost:8080

11. [EXPORT] Export BigQuery data to GCS (optional)

Local run:

```bash
set -a; source .env; set +a
pip install -r requirements.txt
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export BIGQUERY_PROJECT_ID=your-gcp-project
export EXPORT_GCS_BUCKET_NAME=your-export-bucket
export EXPORT_TABLE_MAP='{"public_headline":"dev/exports/headline.json","public_airline_breakdown":"dev/exports/airline_breakdown.json","public_tops":"dev/exports/tops.json","public_bucket_distribution":"dev/exports/bucket_distribution.json","public_daily_status":"dev/exports/daily_status.json"}'
export EXPORT_BQ_DATASET_ID=marts
python scripts/export_to_gcs.py
```

Required env vars: `BIGQUERY_PROJECT_ID`, `EXPORT_GCS_BUCKET_NAME` (or `GCS_BUCKET_NAME`).
Optional overrides: `EXPORT_TABLE_MAP`, `EXPORT_GCS_BLOB_PATH`, `EXPORT_BQ_DATASET_ID`,
`EXPORT_BQ_TABLE_ID`, `EXPORT_BQ_DATE_COLUMN`, `EXPORT_BQ_LOOKBACK_DAYS`, `EXPORT_BQ_LIMIT`.

Dataset selection:

- Prod builds (target `prod`) create marts in dataset `marts`, so use
  `EXPORT_BQ_DATASET_ID=marts`.
- Dev builds (target `dev`) create models in `SANDBOX_<DBT_USER>`, so use
  `EXPORT_BQ_DATASET_ID=SANDBOX_<DBT_USER>` (for example `SANDBOX_JUAN`).

Bucket path selection:

- Local runs default to `dev/exports/...` (for example `EXPORT_GCS_BLOB_PATH=dev/exports/routes_metrics.json`).
- GitHub Actions should use a prod prefix like `prod/exports/...` to keep outputs separate.

Exports produced when using `EXPORT_TABLE_MAP`:

- `headline.json`
- `airline_breakdown.json`
- `tops.json`
- `bucket_distribution.json`
- `daily_status.json`

If you see `ModuleNotFoundError: No module named 'google'`, install dependencies with
`pip install -r requirements.txt` and re-run the script.

Verify the export in GCS:

```bash
gsutil ls "gs://$EXPORT_GCS_BUCKET_NAME/$EXPORT_GCS_BLOB_PATH"
```

GitHub Actions:

- Add secrets:
  - `MELTANO_GOOGLE_APPLICATION_CREDENTIALS` (base64 JSON key)
  - `BIGQUERY_PROJECT_ID`
  - `EXPORT_GCS_BUCKET_NAME` (or `GCS_BUCKET_NAME`)
  - Optional overrides: `EXPORT_BQ_DATASET_ID`, `EXPORT_BQ_TABLE_ID`,
    `EXPORT_BQ_DATE_COLUMN`, `EXPORT_BQ_LOOKBACK_DAYS`, `EXPORT_BQ_LIMIT`,
    `EXPORT_GCS_BLOB_PATH`
- The workflow `.github/workflows/export_bigquery.yml` runs every 6 hours and
  can be triggered manually.

## Next steps

1. View dbt docs to explore the DAG and columns.
2. Add a new model and document it.
3. Change the data source and adapt staging.

## Understanding the project

### Data flow

```
Aeropuertos Argentina API
  -> Meltano (tap-airlines-arg + target-bigquery)
  -> BigQuery: dataset <env>_tap_airlines_arg (raw)
  -> dbt staging: dataset stg (stg_*)
  -> dbt marts: dataset marts (final models)
```

### Staging vs marts

- Staging cleans and normalizes raw data. It keeps consistent names and correct types.
- Marts are final models ready for analysis or BI.

Real example from this project:

- `stg_flights` -> `flights_performance`
- `stg_airlines` -> `airline_metrics`

### Table of models and key columns

All column documentation lives in:

- `transform/models/staging/*.yml`
- `transform/models/production/marts/*.yml`

### Environments (dev, ci, prod)

- dev: default target. Raw data in `dev_tap_airlines_arg`, models in `SANDBOX_<DBT_USER>`.
- ci: optional target. Raw data in `ci_tap_airlines_arg`, models in `stg`/`marts`.
- prod: raw data in `prod_tap_airlines_arg`, models in `stg`/`marts` (deploy/docs).

If you do not pass `--target prod`, dbt uses the default target (dev).

> [!] WARNING: For `dev`, you need `DBT_USER`. If you do not set it, dbt fails in the on-run-start hook.

### Why we use dbt build (and not dbt run)

- `dbt run` only executes models.
- `dbt build` executes models and tests (and snapshots/seeds if they exist).
- In PR and deploy we use `dbt build` to validate everything passes.

### Modeling conventions

- Staging always uses the `stg_` prefix.
- Marts have no prefix (e.g. `github_commits`).
- Each production model has its own `.yml` file with columns and tests.
- Use `ref()` for dependencies between models.

## Local development

### Work in your sandbox (dev)

```bash
export DBT_USER=tu_usuario
cd transform
set -a; source ../.env; set +a
export DBT_PROFILES_DIR=.
dbt build
```

- [i] INFO: Raw data stays in `<target>_tap_airlines_arg` (for example `dev_tap_airlines_arg`),
- but your models are created in `SANDBOX_<DBT_USER>`.
- [i] INFO: If you modify models or YAML, run `dbt build` again.

### Add a new model

1. Create the SQL in `transform/models/staging` or `transform/models/production/marts`.
2. Create the model YAML with descriptions for all columns and basic tests.
3. Run a selective build.

```bash
dbt build --select <nombre_del_modelo>
```

### Change the data source

1. Edit `extraction/meltano.yml` to point to your new extractor or adjust the tap configuration.
2. Update `transform/models/staging/source_airlines.yml` (or any other staging source sheet) with the new dataset and tables.
3. Rewrite the staging models to map the new columns.

## Quick repo layout

- `extraction/`: Meltano project
- `transform/`: dbt project
- `.github/workflows/`: CI/CD
- `.env.example`: variables template

<details>
<summary>CI/CD Setup</summary>

The workflows in `.github/workflows` are configured for this BigQuery stack
(tap-airlines-arg + target-bigquery). Make sure the secrets below are set.

### Required GitHub secrets

- `BIGQUERY_PROJECT_ID`
- `BIGQUERY_DATASET_ID`
- `BIGQUERY_LOCATION`
- `DBT_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `MELTANO_GOOGLE_APPLICATION_CREDENTIALS` (base64-encoded JSON key)
- `DBT_USER` (for sandbox datasets)
- `TAP_AIRLINES_API_KEY`
- `DBT_MANIFEST_URL` for custom slim CI
- `MELTANO_STATE_BACKEND_URI` if you want Meltano state in GCS
- `TARGET_BIGQUERY_PROJECT` if different from `BIGQUERY_PROJECT_ID`
- `TARGET_BIGQUERY_LOCATION` if different from `BIGQUERY_LOCATION`

Encode the JSON key before saving to GitHub Secrets:

```bash
base64 -i /path/to/service-account.json | tr -d '\n'
```

If you ever rotate the key or re-upload a secret, regenerate it with the same command and paste the exact string (no `***`, no line breaks). You can add a quick check in the workflow (`printf '%s' "${{ secrets.DB... }}" | wc -c`) to confirm the secret size before decoding.

### Workflows

- `data-pipeline.yml`: schedule + manual. Runs extraction and then dbt.
- `dbt-pr-ci.yml`: on PR. Runs dbt build in sandbox and lints with SQLFluff.
- `dbt-cd-docs.yml`: on push to `main`. Runs dbt build in prod and publishes docs.

> [i] INFO: PR, deploy, and the scheduled pipeline use `dbt build`.

### Slim CI (prod manifest)

- The PR workflow tries to download `manifest.json` from prod.
- With `state:modified+` and `--defer`, dbt runs only what changed and uses prod for everything else.
- If there is no manifest, it runs a full build.

### SQLFluff

SQLFluff is a SQL linter. It is used to:

- keep consistent style in models
- catch basic issues before running dbt

In PR, only modified SQL models are linted.

### Enable GitHub Pages

1. Go to Settings -> Pages.
2. In Source, choose GitHub Actions.
3. After a push to `main`, the docs are published.

</details>

<details>
<summary>Common troubleshooting</summary>

Error: Env var required but not provided: BIGQUERY_PROJECT_ID

```bash
set -a; source .env; set +a
```

If you are inside `transform` or `extraction`:

```bash
set -a; source ../.env; set +a
```

Error: source: no such file or directory: .env

```bash
set -a; source ../.env; set +a
```

Error: Source dataset not found

Run extraction in the same environment as your dbt target (prod example):

```bash
meltano --environment=prod run tap-airlines-arg target-bigquery
```

Need a full reload (clear Meltano state)

If you want to reimport everything, clear the saved state first:

```bash
meltano --environment=prod state list
meltano --environment=prod state clear prod:tap-airlines-arg-to-target-bigquery --force
```

To clear all state IDs:

```bash
meltano --environment=prod state clear --all --force
```

Error: Required key is missing from config (Meltano)

Make sure `BIGQUERY_*`, `TARGET_BIGQUERY_*`, and Meltano credential paths are set in `.env` and reload:

```bash
set -a; source .env; set +a
```

Error: DBT_USER environment variable not set

```bash
export DBT_USER=tu_usuario
```

</details>

<details>
<summary>Template customization</summary>

- For another API: replace the tap in `extraction/meltano.yml`.
- For another warehouse: update `transform/profiles.yml.example` and `BIGQUERY_*`/`TARGET_BIGQUERY_*` in `.env`.
- For new models: add SQL in `transform/models/production/marts` and its YAML next to it.

</details>

## License

MIT
