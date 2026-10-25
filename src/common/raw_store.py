"""raw_store: the ONLY place that writes to the raw.* tables (code rule 3).

Connection settings (first match wins):
  1. ECO_DB_URL            full URL, e.g. postgresql://etl_user:pw@localhost:5432/eco
  2. AIRFLOW_CONN_ECO_DB   already set inside the Airflow containers
  3. POSTGRES_HOST / POSTGRES_PORT / POSTGRES_DB / ETL_USER / ETL_USER_PASSWORD
     (defaults: localhost, 5432, eco, etl_user)
"""
import os


def _connect():
    import psycopg2  # imported here so tests and parsers work without a database

    url = os.getenv("ECO_DB_URL") or os.getenv("AIRFLOW_CONN_ECO_DB")
    if url:
        return psycopg2.connect(url)
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "eco"),
        user=os.getenv("ETL_USER", "etl_user"),
        password=os.getenv("ETL_USER_PASSWORD"),
    )


def _insert(sql, params):
    conn = _connect()
    try:
        with conn:  # one transaction: commit on success, rollback on error
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchone()[0]
    finally:
        conn.close()


def store_api_response(source, endpoint, http_status, payload):
    """Save a JSON API response untouched. Returns the new raw.api_responses id."""
    from psycopg2.extras import Json

    return _insert(
        "INSERT INTO raw.api_responses (source, endpoint, http_status, payload) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (source, endpoint, http_status, Json(payload)),
    )


def store_html_page(source, url, http_status, html):
    """Save an HTML page untouched (used by Role 2's scraper)."""
    return _insert(
        "INSERT INTO raw.html_pages (source, url, http_status, html) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (source, url, http_status, html),
    )


def store_file(source, file_name, file_path, sha256=None, size_bytes=None):
    """Register an official file that lives on the volume in raw.files."""
    return _insert(
        "INSERT INTO raw.files (source, file_name, file_path, sha256, size_bytes) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id",
        (source, file_name, file_path, sha256, size_bytes),
    )
