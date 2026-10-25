ARG AIRFLOW_VERSION=2.11.0
FROM apache/airflow:${AIRFLOW_VERSION}
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt