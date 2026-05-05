#  Stage 1: builder ─
FROM python:3.12-slim AS builder

WORKDIR /app

# Install dependencies into a prefix for clean copying
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --prefix=/install --no-cache-dir -r requirements.txt


#  Stage 2: runtime 
FROM python:3.12-slim AS runtime

# Security: run as non-root
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY app.py .

USER appuser

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    ENVIRONMENT=production \
    APP_VERSION=1.0.0

EXPOSE 8080

# Health check (Docker-native; ECS also uses this)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Use gunicorn for production (multi-worker WSGI server)
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "2", \
     "--timeout", "60", "--access-logfile", "-", "--error-logfile", "-", \
     "--log-level", "info", "app:app"]
