FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/a2a-probe
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --system --uid 10001 --home-dir /nonexistent probe

COPY app.py .
USER 10001:10001
EXPOSE 8080
# Cloud Run does public TLS termination; the container is reachable only
# through the platform-managed private service port.
CMD ["sh", "-c", "exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080} --no-access-log --log-level error"]
