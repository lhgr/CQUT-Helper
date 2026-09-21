"""Shared HTTP behavior for FastAPI applications.

This module deliberately contains no business state. Applications can install
the same error envelope, validation response, security headers, and a specific
request-body size limit.
"""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ServiceError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def error_response(status_code: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={
            "success": False,
            "error": {"code": code, "message": message},
        },
        headers={
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        },
    )


def install_service_common(app: FastAPI, *, max_body_bytes: int) -> None:
    """Install the shared HTTP contract with a service-specific body limit."""
    if max_body_bytes <= 0:
        raise ValueError("max_body_bytes must be positive")

    @app.middleware("http")
    async def security_headers_and_body_limit(
        request: Request, call_next: Any
    ) -> Any:
        content_length = request.headers.get("content-length", "").strip()
        if content_length:
            try:
                if int(content_length) > max_body_bytes:
                    return error_response(413, "request_too_large", "请求体过大")
            except ValueError:
                pass

        # Content-Length is not guaranteed (for example for chunked HTTP), so
        # also enforce the limit against the bytes Starlette actually receives.
        body = await request.body()
        if len(body) > max_body_bytes:
            return error_response(413, "request_too_large", "请求体过大")

        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(ServiceError)
    async def service_error_handler(
        _request: Request, exc: ServiceError
    ) -> JSONResponse:
        return error_response(exc.status_code, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        _request: Request, _exc: RequestValidationError
    ) -> JSONResponse:
        return error_response(422, "validation_error", "请求参数不合法")
