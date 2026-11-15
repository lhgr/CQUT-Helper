FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers \
    HOME=/tmp

WORKDIR /app
COPY FastAPI/requirements.txt /app/FastAPI/requirements.txt
RUN apt-get update \
    && apt-get install -y --no-install-recommends libatomic1 \
    && python -m pip install --no-cache-dir -r FastAPI/requirements.txt \
    && python -m playwright install --with-deps chromium \
    && chmod -R a+rX /opt/pw-browsers \
    && groupadd --gid 10001 notice \
    && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /tmp notice \
    && rm -rf /var/lib/apt/lists/*

# Only public query code is copied; no private calendar module or database.
COPY FastAPI/main.py FastAPI/jwxt_automation.py FastAPI/exam_queries.py FastAPI/service_common.py FastAPI/check_browser_sandbox.py /app/FastAPI/
USER 10001:10001
EXPOSE 8001
CMD ["python", "-m", "uvicorn", "FastAPI.main:app", "--host", "0.0.0.0", "--port", "8001", "--no-proxy-headers", "--workers", "1"]
