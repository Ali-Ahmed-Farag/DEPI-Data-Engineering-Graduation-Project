from airflow.decorators import dag, task
from datetime import datetime, timedelta

@dag(schedule="@daily", start_date=datetime(2026, 10, 1), catchup=False,
     default_args={"retries": 3, "retry_delay": timedelta(minutes=5)})
def hello_dag():
    @task
    def extract():
        return "ok"

    @task
    def load(x):
        print(x)

    load(extract())

hello_dag()