# SPDX-FileCopyrightText: 2023 Marlon W (Mawoka)
#
# SPDX-License-Identifier: MPL-2.0

# Use a specific version for better reproducibility.
# Stage 1: Builder - to generate requirements.txt and isolate build tools like jq.
FROM python:3.11.6-slim-bookworm as builder

WORKDIR /build-workspace

# Copy dependency files first
COPY Pipfile Pipfile.lock ./

# Install system dependencies and Python packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    jq \
    gcc \
    libpq5 \
    libpq-dev \
    libmagic1 && \
    jq -r '.default | to_entries[] | .key + .value.version' Pipfile.lock > requirements.txt && \
    sed -i "s/psycopg2-binary/psycopg2/g" requirements.txt && \
    pip install -r requirements.txt && \
    apt-get remove -y jq gcc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy application code
COPY classquiz/ ./classquiz/
COPY image_cleanup.py ./
COPY alembic.ini ./
COPY migrations/ ./migrations/
COPY *start.sh ./
COPY gunicorn_conf.py ./

EXPOSE 80
ENV PYTHONPATH=/app
RUN chmod +x start.sh
ENV APP_MODULE=classquiz:app
CMD ["./start.sh"]
