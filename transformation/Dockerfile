FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir "dbt-bigquery>=1.10,<2.0"

COPY . .

CMD ["dbt", "build", "--profiles-dir", "."]
