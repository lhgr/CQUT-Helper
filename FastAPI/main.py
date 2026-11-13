"""Self-hosted CQUT schedule notice service."""

from fastapi import FastAPI

from FastAPI.jwxt_automation import router as jwxt_router
from FastAPI.service_common import install_service_common

app = FastAPI(title="CQUT Helper API", version="1.0.0")
install_service_common(app)
app.include_router(jwxt_router)


@app.get("/health")
def health() -> dict[str, object]:
    return {"status": "ok", "ready": True}
