from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.operators.python import PythonOperator


def extract():
    print("extract: hello from Airflow")


def load():
    print("load: done")


with DAG(
    dag_id="hello_dag",
    start_date=pendulum.datetime(2026, 10, 1, tz="Africa/Cairo"),
    schedule="0 6 * * *",          # يومي 06:00 بتوقيت القاهرة
    catchup=False,
    default_args={"retries": 3, "retry_delay": timedelta(minutes=5)},
    tags=["test"],
) as dag:
    t_extract = PythonOperator(task_id="extract", python_callable=extract)
    t_load = PythonOperator(task_id="load", python_callable=load)

    t_extract >> t_load