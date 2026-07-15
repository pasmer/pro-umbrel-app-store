"""JARVIS Mission Control.

Small, headless web bridge between the browser and a Hermes Agent API server.
The Hermes API key is read only on the server, never sent to the browser.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, AsyncIterator

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

HERMES_API_URL = os.getenv("HERMES_API_URL", "http://hermes-agent_web_1:8642").rstrip("/")
HERMES_API_KEY_FILE = Path(os.getenv("HERMES_API_KEY_FILE", "/data/hermes_api_key"))
DEFAULT_CONVERSATION = os.getenv("HERMES_CONVERSATION", "jarvis-mission-control")
REQUEST_TIMEOUT = float(os.getenv("HERMES_REQUEST_TIMEOUT", "180"))

app = FastAPI(title="JARVIS Mission Control", version="0.1.0")


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=20_000)
    conversation: str = Field(default=DEFAULT_CONVERSATION, min_length=1, max_length=256)
    instructions: str | None = Field(default=None, max_length=4_000)


class RunRequest(BaseModel):
    input: str = Field(min_length=1, max_length=20_000)
    session_id: str | None = Field(default=None, max_length=256)
    instructions: str | None = Field(default=None, max_length=4_000)


def _api_key() -> str:
    value = os.getenv("HERMES_API_KEY", "").strip()
    if value:
        return value
    try:
        return HERMES_API_KEY_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _headers(*, json_body: bool = False, conversation: str | None = None) -> dict[str, str]:
    key = _api_key()
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    if json_body:
        headers["Content-Type"] = "application/json"
    if conversation:
        headers["X-Hermes-Session-Key"] = f"jarvis:mission-control:{conversation}"
        headers["X-Hermes-Session-Id"] = conversation
    return headers


def _error_message(response: httpx.Response) -> str:
    try:
        data = response.json()
        if isinstance(data, dict):
            return str(data.get("error") or data.get("message") or data)
    except Exception:
        pass
    return response.text[:500] or f"Hermes returned HTTP {response.status_code}"


def _response_text(payload: dict[str, Any]) -> str:
    """Extract text from either Responses API or Chat Completions output."""
    choices = payload.get("choices") or []
    if choices:
        message = choices[0].get("message") or {}
        content = message.get("content", "")
        if isinstance(content, str):
            return content

    output = payload.get("output") or []
    parts: list[str] = []
    for item in output:
        if not isinstance(item, dict) or item.get("type") not in (None, "message"):
            continue
        content = item.get("content") or []
        if isinstance(content, str):
            parts.append(content)
            continue
        for block in content:
            if isinstance(block, dict):
                text = block.get("text") or block.get("output_text")
                if text:
                    parts.append(str(text))
    return "".join(parts).strip()


async def _get(path: str, *, authenticated: bool = True) -> httpx.Response:
    headers = _headers() if authenticated else {}
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        return await client.get(f"{HERMES_API_URL}{path}", headers=headers)


@app.get("/", include_in_schema=False)
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/status")
async def status() -> JSONResponse:
    result: dict[str, Any] = {
        "jarvis": "online",
        "hermes_url": HERMES_API_URL,
        "api_key_configured": bool(_api_key()),
        "hermes": "offline",
        "capabilities": None,
    }
    try:
        health = await _get("/health", authenticated=False)
        result["hermes"] = "online" if health.is_success else "error"
        result["hermes_health"] = health.json() if health.content else None
    except Exception as exc:
        result["error"] = str(exc)

    if result["api_key_configured"] and result["hermes"] == "online":
        try:
            capabilities = await _get("/v1/capabilities")
            if capabilities.is_success:
                result["capabilities"] = capabilities.json()
        except Exception:
            pass
    return JSONResponse(result)


@app.get("/api/capabilities")
async def capabilities() -> JSONResponse:
    if not _api_key():
        raise HTTPException(status_code=503, detail="Hermes API key is not configured")
    try:
        response = await _get("/v1/capabilities")
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Hermes unavailable: {exc}") from exc
    if not response.is_success:
        raise HTTPException(status_code=response.status_code, detail=_error_message(response))
    return JSONResponse(response.json())


def _response_payload(request: ChatRequest, *, stream: bool) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": "hermes-agent",
        "input": request.message,
        "conversation": request.conversation,
        "store": True,
        "stream": stream,
    }
    if request.instructions:
        payload["instructions"] = request.instructions
    return payload


@app.post("/api/chat")
async def chat(request: ChatRequest) -> JSONResponse:
    if not _api_key():
        raise HTTPException(status_code=503, detail="Hermes API key is not configured")
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            response = await client.post(
                f"{HERMES_API_URL}/v1/responses",
                headers=_headers(json_body=True, conversation=request.conversation),
                json=_response_payload(request, stream=False),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Hermes unavailable: {exc}") from exc
    if not response.is_success:
        raise HTTPException(status_code=response.status_code, detail=_error_message(response))
    payload = response.json()
    return JSONResponse({"text": _response_text(payload), "response": payload})


@app.post("/api/chat/stream")
async def chat_stream(request: ChatRequest) -> StreamingResponse:
    if not _api_key():
        raise HTTPException(status_code=503, detail="Hermes API key is not configured")

    async def event_stream() -> AsyncIterator[str]:
        try:
            async with httpx.AsyncClient(timeout=None) as client:
                async with client.stream(
                    "POST",
                    f"{HERMES_API_URL}/v1/responses",
                    headers=_headers(json_body=True, conversation=request.conversation),
                    json=_response_payload(request, stream=True),
                ) as response:
                    if not response.is_success:
                        body = await response.aread()
                        message = body.decode("utf-8", errors="replace")[:500]
                        yield f"event: error\ndata: {json.dumps({'error': message})}\n\n"
                        return
                    async for line in response.aiter_lines():
                        yield f"{line}\n"
        except Exception as exc:
            yield f"event: error\ndata: {json.dumps({'error': str(exc)})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/runs")
async def create_run(request: RunRequest) -> JSONResponse:
    """Create a long-running Hermes run for clients that need explicit control."""
    if not _api_key():
        raise HTTPException(status_code=503, detail="Hermes API key is not configured")
    body: dict[str, Any] = {"input": request.input}
    if request.session_id:
        body["session_id"] = request.session_id
    if request.instructions:
        body["instructions"] = request.instructions
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            response = await client.post(
                f"{HERMES_API_URL}/v1/runs",
                headers=_headers(json_body=True, conversation=request.session_id),
                json=body,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Hermes unavailable: {exc}") from exc
    if not response.is_success:
        raise HTTPException(status_code=response.status_code, detail=_error_message(response))
    return JSONResponse(response.json())


@app.post("/api/runs/{run_id}/stop")
async def stop_run(run_id: str) -> JSONResponse:
    if not _api_key():
        raise HTTPException(status_code=503, detail="Hermes API key is not configured")
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            response = await client.post(
                f"{HERMES_API_URL}/v1/runs/{run_id}/stop",
                headers=_headers(json_body=True),
                json={},
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Hermes unavailable: {exc}") from exc
    if not response.is_success:
        raise HTTPException(status_code=response.status_code, detail=_error_message(response))
    return JSONResponse(response.json())
