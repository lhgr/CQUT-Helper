"""Shared HTTP behavior for FastAPI applications.

This module contains no business state. The application installs a shared
error envelope, validation response, security headers, and path-specific
request-body size limits.
"""

import asyncio
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


def install_service_common(app: FastAPI) -> None:
    """Install shared errors and route-specific request body limits."""

    app.add_middleware(BodyLimitMiddleware)

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


class BodyLimitMiddleware:
    def __init__(self, app: Any, read_timeout: float = 10.0):
        self.app, self.read_timeout = app, read_timeout

    async def __call__(self, scope: Any, receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        maximum = 20480 if scope["path"].startswith("/api/jwxt/") else 65536
        try:
            declared = int(dict(scope.get("headers", [])).get(b"content-length", b"0"))
        except ValueError:
            declared = 0
        if declared > maximum:
            await error_response(413, "request_too_large", "请求体过大")(scope, receive, send)
            return
        chunks, size = [], 0
        deadline = asyncio.get_running_loop().time() + self.read_timeout
        while True:
            try:
                message = await asyncio.wait_for(receive(), max(0, deadline - asyncio.get_running_loop().time()))
            except asyncio.TimeoutError:
                await error_response(408, "request_timeout", "请求体读取超时")(scope, receive, send)
                return
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            size += len(message.get("body", b""))
            if size > maximum:
                await error_response(413, "request_too_large", "请求体过大")(scope, receive, send)
                return
            chunks.append(message)
            if not message.get("more_body", False):
                break
        iterator = iter(chunks)
        async def replay() -> Any:
            try:
                return next(iterator)
            except StopIteration:
                return await receive()
        async def with_headers(message: Any) -> None:
            if message["type"] == "http.response.start":
                message = dict(message)
                message["headers"] = [(k, v) for k, v in message.get("headers", []) if k.lower() not in {b"cache-control", b"x-content-type-options"}]
                message["headers"].extend([(b"cache-control", b"no-store"), (b"x-content-type-options", b"nosniff")])
            await send(message)
        await self.app(scope, replay, with_headers)
