"""Argus read-only provider usage service."""

from __future__ import annotations

import argparse
import logging
import secrets

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

import argus_data
from api_contract import snapshot
from config import settings

logging.basicConfig(level=str(settings.get("logging.level", "INFO")))
log = logging.getLogger("argus")

app = FastAPI(title="Argus", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.get("server.cors_origins", [])),
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["Authorization"],
)


def require_client_token(request: Request) -> None:
    """Protect the client-facing contract when local config enables a token."""
    expected = settings.env_value("api.bearer_token_env")
    if not expected:
        return
    presented = request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not secrets.compare_digest(presented, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")


@app.get("/api/v1/health", dependencies=[Depends(require_client_token)])
def v1_health():
    return {"ok": True, "schema_version": 1, "service": "argus"}


@app.get("/api/v1/snapshot", dependencies=[Depends(require_client_token)])
def v1_snapshot():
    return snapshot(
        argus_data.providers(),
        argus_data.balances(),
        str(settings.get("integrations.kallisti.dashboard_url", "")),
    )


# Legacy dashboard endpoints can be disabled from config before public exposure.
@app.get("/api/health")
def health():
    return {"ok": True, "service": "argus"}


@app.get("/api/all")
def api_all():
    if not settings.get("api.expose_internal_endpoints", False):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return {
        "totals": argus_data.totals(),
        "usage": {"summary": argus_data.usage_summary(30), "by_day": argus_data.usage_by_day(14)},
        "providers": argus_data.providers(),
        "balances": argus_data.balances(),
        "generated_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    }


@app.get("/")
def index():
    return FileResponse("static/index.html")


app.mount("/static", StaticFiles(directory="static"), name="static")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=str(settings.get("server.host", "127.0.0.1")))
    parser.add_argument("--port", type=int, default=int(settings.get("server.port", 8090)))
    args = parser.parse_args()
    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port, log_level=str(settings.get("logging.level", "info")).lower())


if __name__ == "__main__":
    main()
