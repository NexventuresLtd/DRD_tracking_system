#!/usr/bin/env python3
"""
DRD Reticulum Bridge  v2  — LXMF + Raw packet gateway
=======================================================
Runs as a sidecar alongside the DRD FastAPI server.
Supports two operation modes simultaneously:

  1. LXMF mode  — Sideband (Android/iOS) and other LXMF apps send messages to
                   the bridge's LXMF destination.  Text messages that begin with
                   '{' are parsed as JSON commands; all others become chat messages
                   forwarded to the DRD comms channel.

  2. Raw packet  — Custom Flutter/Python field clients send raw msgpack packets
                   (same protocol as v1) for high-throughput telemetry.

Flow
────
  Phone/Sideband  ──LXMF──▶  bridge  ──HTTP──▶  FastAPI  ──DB──▶  dashboard
  FastAPI WS      ──event──▶  bridge  ──LXMF──▶  Phone/Sideband
  Field computer  ──msgpack─▶ bridge  ──HTTP──▶  FastAPI

Environment variables (see .env.example)
─────────────────────────────────────────
  API_BASE_URL        http://127.0.0.1:8000  (or public URL)
  API_TOKEN           Service-account JWT (created via admin panel)
  WS_URL              ws://127.0.0.1:8000/ws/events?token=<API_TOKEN>
  RNS_APP_NAME        drd
  RNS_APP_ASPECT      bridge
  RNS_CONFIG_DIR      ~/.reticulum
  RNS_IDENTITY_PATH   ~/.reticulum/drd_bridge_identity  (persisted identity)
  ANNOUNCE_INTERVAL   300  (seconds between RNS announces)
  BRIDGE_LOG_LEVEL    INFO
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

import aiohttp
import msgpack
import RNS
import LXMF

# ── Configuration ──────────────────────────────────────────────────────────────

API_BASE          = os.getenv("API_BASE_URL",      "http://127.0.0.1:8000")
API_TOKEN         = os.getenv("API_TOKEN",         "")
WS_URL            = os.getenv("WS_URL",            f"ws://127.0.0.1:8000/ws/events")
APP_NAME          = os.getenv("RNS_APP_NAME",      "drd")
APP_ASPECT        = os.getenv("RNS_APP_ASPECT",    "bridge")
CONFIG_DIR        = os.getenv("RNS_CONFIG_DIR",    str(Path.home() / ".reticulum"))
IDENTITY_PATH     = os.getenv("RNS_IDENTITY_PATH", str(Path.home() / ".reticulum" / "drd_bridge_identity"))
ANNOUNCE_INTERVAL = int(os.getenv("ANNOUNCE_INTERVAL", "300"))

LOG_LEVEL = getattr(logging, os.getenv("BRIDGE_LOG_LEVEL", "INFO").upper(), logging.INFO)
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(name)s  %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("drd.bridge")

# ── Global state ───────────────────────────────────────────────────────────────

# hex_hash → {"lxmf": bool, "dest": RNS.Destination | None}
_peers: dict[str, dict] = {}
_loop: Optional[asyncio.AbstractEventLoop] = None
_inbound: asyncio.Queue = asyncio.Queue()

# ── Identity: persist so the bridge hash never changes across restarts ─────────

def _load_or_create_identity() -> RNS.Identity:
    path = Path(IDENTITY_PATH)
    if path.exists():
        identity = RNS.Identity.from_file(str(path))
        log.info("Loaded persistent identity from %s", path)
    else:
        identity = RNS.Identity()
        path.parent.mkdir(parents=True, exist_ok=True)
        identity.to_file(str(path))
        log.info("Created new identity — saved to %s", path)
    return identity

# ── Packet codec ───────────────────────────────────────────────────────────────

def _unpack(raw: bytes) -> Optional[dict]:
    try:
        return msgpack.unpackb(raw, raw=False)
    except Exception:
        try:
            return json.loads(raw)
        except Exception:
            return None

def _pack(data: dict) -> bytes:
    return msgpack.packb(data, use_bin_type=True)

# ── API helpers ────────────────────────────────────────────────────────────────

async def _post(session: aiohttp.ClientSession, path: str, body: dict, token: str) -> Optional[dict]:
    url = f"{API_BASE}{path}"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    try:
        async with session.post(url, json=body, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as r:
            if r.status in (200, 201):
                return await r.json()
            log.warning("API %s → %s", path, r.status)
    except Exception as exc:
        log.warning("API call failed (%s): %s", path, exc)
    return None

# ── Packet dispatchers ─────────────────────────────────────────────────────────

async def _handle_location(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {k: pkt[k] for k in ("latitude", "longitude", "altitude", "speed", "heading", "accuracy") if k in pkt}
    body["recorded_at"] = pkt.get("recorded_at", datetime.now(timezone.utc).isoformat())
    if await _post(session, "/api/v1/locations", body, token):
        log.info("Location stored uid=%s", str(pkt.get("user_id", "?"))[:8])

async def _handle_sos(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {
        "latitude":  pkt.get("latitude"),
        "longitude": pkt.get("longitude"),
        "message":   pkt.get("message", "SOS via Reticulum mesh"),
    }
    if await _post(session, "/api/v1/sos", body, token):
        log.warning("SOS triggered uid=%s", str(pkt.get("user_id", "?"))[:8])

async def _handle_message(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {"content": pkt.get("content", ""), "channel": pkt.get("channel", "global")}
    await _post(session, "/api/v1/messages", body, token)

async def _handle_poi(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    payload = pkt.get("payload", pkt)
    body = {k: payload[k] for k in ("name", "latitude", "longitude", "poi_type", "color", "description") if k in payload}
    body.setdefault("name", payload.get("poi_type", "mark").capitalize())
    if await _post(session, "/api/v1/pois", body, token):
        log.info("POI stored via mesh: %s", body.get("name"))

async def _dispatch(session: aiohttp.ClientSession, pkt: dict):
    t = pkt.get("type", "")
    if   t == "location_update": await _handle_location(session, pkt)
    elif t == "location":         await _handle_location(session, pkt)
    elif t == "sos":              await _handle_sos(session, pkt)
    elif t == "message":          await _handle_message(session, pkt)
    elif t == "poi":              await _handle_poi(session, pkt)
    elif t == "ping":
        src = pkt.get("_src_hash")
        if src:
            _send_raw(src, {"type": "pong", "ts": time.time()})
    else:
        log.debug("Unknown type: %s", t)

# ── Outbound helpers ───────────────────────────────────────────────────────────

def _send_raw(dest_hash: str, payload: dict):
    try:
        dest_bytes = bytes.fromhex(dest_hash)
        dest = RNS.Destination.recall(dest_bytes)
        if dest is None:
            return
        RNS.Packet(dest, _pack(payload)).send()
    except Exception as exc:
        log.debug("Raw send to %s failed: %s", dest_hash[:8], exc)

def _send_lxmf(router: LXMF.LXMRouter, lxmf_dest: LXMF.LXMPeer, peer_hash: str, text: str):
    try:
        dest_bytes = bytes.fromhex(peer_hash)
        dest_id    = RNS.Identity.recall(dest_bytes)
        if dest_id is None:
            RNS.Transport.request_path(dest_bytes)
            log.debug("Requested path to %s, will retry when known", peer_hash[:8])
            return
        dest = RNS.Destination(dest_id, RNS.Destination.OUT, RNS.Destination.SINGLE, "lxmf", "delivery")
        msg  = LXMF.LXMessage(dest, lxmf_dest, text, desired_method=LXMF.LXMessage.DIRECT)
        router.handle_outbound(msg)
        log.debug("LXMF sent to %s", peer_hash[:8])
    except Exception as exc:
        log.warning("LXMF send failed: %s", exc)

def _broadcast_all(router: LXMF.LXMRouter, lxmf_dest: LXMF.LXMPeer, payload: dict):
    text = json.dumps(payload, separators=(",", ":"))
    for h, meta in list(_peers.items()):
        if meta.get("lxmf"):
            _send_lxmf(router, lxmf_dest, h, text)
        else:
            _send_raw(h, {"type": "broadcast", "payload": payload})

# ── LXMF message handler ───────────────────────────────────────────────────────

def _on_lxmf(message: LXMF.LXMessage):
    """Called by LXMF router when a message arrives from a phone/Sideband."""
    src_hash = message.source_hash.hex() if message.source_hash else None
    content  = message.content_as_string() if message.content else ""
    log.info("LXMF from %s: %s", (src_hash or "?")[:8], content[:80])

    if src_hash:
        _peers[src_hash] = {"lxmf": True}

    pkt: dict = {}
    stripped = content.strip()
    if stripped.startswith("{"):
        try:
            pkt = json.loads(stripped)
        except json.JSONDecodeError:
            pass

    if not pkt:
        # Plain text — treat as a global chat message
        pkt = {"type": "message", "content": content, "channel": "global"}

    pkt.setdefault("type", "message")
    if src_hash:
        pkt["_src_hash"] = src_hash

    if _loop and not _loop.is_closed():
        asyncio.run_coroutine_threadsafe(_inbound.put(pkt), _loop)

# ── Raw RNS packet handler ─────────────────────────────────────────────────────

def _on_raw_packet(pkt_obj: RNS.Packet):
    raw = pkt_obj.plaintext
    pkt = _unpack(raw)
    if pkt is None:
        return
    if pkt_obj.destination:
        h = pkt_obj.destination.hash.hex()
        _peers.setdefault(h, {"lxmf": False})
        pkt["_src_hash"] = h
    log.debug("Raw packet: type=%s", pkt.get("type"))
    if _loop and not _loop.is_closed():
        asyncio.run_coroutine_threadsafe(_inbound.put(pkt), _loop)

# ── Workers ────────────────────────────────────────────────────────────────────

async def _packet_worker(session: aiohttp.ClientSession):
    while True:
        pkt = await _inbound.get()
        try:
            await _dispatch(session, pkt)
        except Exception as exc:
            log.error("Dispatch error: %s", exc)
        finally:
            _inbound.task_done()

async def _ws_subscriber(router: LXMF.LXMRouter, lxmf_dest: LXMF.LXMPeer):
    import websockets
    url = f"{WS_URL}?token={API_TOKEN}" if API_TOKEN else WS_URL
    while True:
        try:
            async with websockets.connect(url) as ws:
                log.info("WS subscriber connected")
                async for raw in ws:
                    try:
                        data = json.loads(raw)
                    except Exception:
                        continue
                    if _peers:
                        _broadcast_all(router, lxmf_dest, data)
        except Exception as exc:
            log.warning("WS disconnected: %s — retry in 5s", exc)
            await asyncio.sleep(5)

async def _announce_loop(dest: RNS.Destination, lxmf_dest: LXMF.LXMPeer):
    while True:
        dest.announce()
        lxmf_dest.announce()
        log.info("Announced bridge (RNS %s)", RNS.prettyhexrep(dest.hash))
        await asyncio.sleep(ANNOUNCE_INTERVAL)

# ── HTTP sync server (Flutter mesh → server when on same LAN) ─────────────────
# Phones POST /mesh/sync with a JSON array of MeshMessage envelopes.
# The bridge authenticates with Authorization: Bearer <token> and forwards
# each message to the DRD server via the existing _dispatch pipeline.

HTTP_PORT = int(os.getenv("BRIDGE_HTTP_PORT", "4344"))

async def _http_mesh_sync(request: aiohttp.web.Request) -> aiohttp.web.Response:
    auth = request.headers.get("Authorization", "")
    if API_TOKEN and auth != f"Bearer {API_TOKEN}":
        return aiohttp.web.json_response({"error": "unauthorized"}, status=401)
    try:
        body = await request.json()
    except Exception:
        return aiohttp.web.json_response({"error": "bad json"}, status=400)

    messages = body if isinstance(body, list) else [body]
    session: aiohttp.ClientSession = request.app["session"]
    queued = 0
    for msg in messages:
        if isinstance(msg, dict):
            await _inbound.put(msg)
            queued += 1
    log.info("HTTP /mesh/sync: queued %d messages from %s", queued, request.remote)
    return aiohttp.web.json_response({"queued": queued})

async def _http_ping(request: aiohttp.web.Request) -> aiohttp.web.Response:
    """Health-check so phones can discover the bridge via a LAN sweep."""
    return aiohttp.web.json_response({"service": "drd-reticulum-bridge", "port": HTTP_PORT})

async def _start_http_server(session: aiohttp.ClientSession):
    app = aiohttp.web.Application()
    app["session"] = session
    app.router.add_post("/mesh/sync", _http_mesh_sync)
    app.router.add_get("/mesh/ping", _http_ping)
    runner = aiohttp.web.AppRunner(app)
    await runner.setup()
    site = aiohttp.web.TCPSite(runner, "0.0.0.0", HTTP_PORT)
    await site.start()
    log.info("HTTP sync server listening on 0.0.0.0:%d", HTTP_PORT)
    return runner

# ── Main ───────────────────────────────────────────────────────────────────────

async def main():
    global _loop
    _loop = asyncio.get_running_loop()

    # Ensure Reticulum config exists
    config_path = Path(CONFIG_DIR) / "config"
    if not config_path.exists():
        import shutil
        config_path.parent.mkdir(parents=True, exist_ok=True)
        bundled = Path(__file__).parent / "reticulum.config"
        shutil.copy(bundled, config_path)
        log.info("Copied default RNS config to %s", config_path)

    # Start Reticulum
    rns = RNS.Reticulum(configdir=CONFIG_DIR)

    # Persistent identity
    identity = _load_or_create_identity()

    # Raw RNS destination (for custom clients)
    raw_dest = RNS.Destination(identity, RNS.Destination.IN, RNS.Destination.SINGLE, APP_NAME, APP_ASPECT)
    raw_dest.set_proof_strategy(RNS.Destination.PROVE_ALL)
    raw_dest.set_packet_callback(_on_raw_packet)

    # LXMF router (for Sideband phones)
    lxmf_router = LXMF.LXMRouter(storagepath=str(Path(CONFIG_DIR) / "lxmf_store"))
    lxmf_dest   = lxmf_router.register_delivery_identity(identity, display_name="DRD Bridge")
    lxmf_router.register_delivery_callback(_on_lxmf)

    log.info("Bridge ready")
    log.info("  RNS  destination : %s  (raw msgpack)", RNS.prettyhexrep(raw_dest.hash))
    log.info("  LXMF destination : %s  (Sideband / phones)", RNS.prettyhexrep(lxmf_dest.hash))
    log.info("  API endpoint     : %s", API_BASE)
    log.info("  Peers known      : %d", len(_peers))

    async with aiohttp.ClientSession() as session:
        stop = asyncio.Event()

        def _sig(sig, _):
            log.info("Signal %s → shutting down", sig)
            stop.set()
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, _sig)

        http_runner = await _start_http_server(session)

        tasks = [
            asyncio.create_task(_packet_worker(session),                 name="packet-worker"),
            asyncio.create_task(_ws_subscriber(lxmf_router, lxmf_dest), name="ws-subscriber"),
            asyncio.create_task(_announce_loop(raw_dest, lxmf_dest),     name="announce"),
        ]

        await stop.wait()
        log.info("Stopping bridge…")
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await http_runner.cleanup()

    log.info("Bridge stopped.")

if __name__ == "__main__":
    if sys.version_info < (3, 11):
        sys.exit("Python 3.11+ required")
    asyncio.run(main())
