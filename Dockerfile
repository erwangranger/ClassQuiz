# SPDX-FileCopyrightText: 2023 Marlon W (Mawoka)
#
# SPDX-License-Identifier: MPL-2.0

# Use a specific version for better reproducibility.
# Stage 1: Builder - to generate requirements.txt and isolate build tools like jq.
FROM python:3.11.6-slim-bookworm as builder

WORKDIR /build-workspace

COPY Pipfile* /app/

# Install build-time dependencies (jq for Pipfile.lock parsing)
# Use --no-install-recommends to reduce image size. Clean up apt cache.
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq && \
    jq -r '.default | to_entries[] | .key + .value.version' Pipfile.lock > requirements.txt && \
    sed -i "s/psycopg2-binary/psycopg2/g" requirements.txt && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Final application image
FROM python:3.11.6-slim-bookworm

WORKDIR /app

# Create a non-root user and group for security.
# OpenShift runs containers with an arbitrary UID by default, but having a defined user is good practice.
RUN groupadd --system --gid 1001 appgroup && \
    useradd --system --uid 1001 --gid appgroup --shell /sbin/nologin --create-home appuser

# Install runtime dependencies (libpq5 for PostgreSQL client, libmagic1 for python-magic)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 libmagic1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements.txt from builder stage
COPY --from=builder /build-workspace/requirements.txt /app/requirements.txt

# Install Python dependencies.
# psycopg2 (non-binary) requires gcc and libpq-dev to compile.
# Install these build tools, then install packages, then remove the build tools.
# Using --no-cache-dir for pip to reduce image size.
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    pip install --no-cache-dir -r requirements.txt && \
    apt-get purge -y --auto-remove gcc libpq-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY classquiz/ /app/classquiz/
COPY image_cleanup.py /app/image_cleanup.py
COPY alembic.ini /app/
COPY migrations/ /app/migrations/
COPY *start.sh /app/
COPY gunicorn_conf.py /app/

# Ensure scripts are executable and set ownership for the app user
RUN chmod +x /app/*start.sh && \
    chown -R appuser:appgroup /app

EXPOSE 80
ENV PYTHONPATH=/app
ENV APP_MODULE=classquiz:app

# Switch to the non-root user
USER appuser

CMD ["./start.sh"]
