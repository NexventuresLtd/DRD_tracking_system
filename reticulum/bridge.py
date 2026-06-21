#!/usr/bin/env python3
"""
DRD Reticulum Bridge
====================
Bidirectional gateway between the Reticulum mesh radio network and the
DRD FastAPI server.  Run this as a sidecar process on any node that has
both a Reticulum interface (serial LoRa / UDP) AND IP connectivity to the
FastAPI server.

Flow
────
  Field radio  ──RNS packet──▶  bridge  ──HTTP POST──▶  FastAPI
  FastAPI WS   ──broadcast──▶   bridge  ──RNS packet──▶  field radio

Packet format (inbound from field units)
─────────────────────────────────────────
  All packets are msgpack-encoded dicts with at minimum:
    { "type": "<msg_type>", "user_id": "<uuid>", "token": "<jwt>", ... }

  Supported types:
    location_update  – forward to POST /api/v1/locations
    sos              – create FLAG event via POST /api/v1/events
    message          – forward to POST /api/v1/messages
    ping             – echo back a pong (no API call)

Packet format (outbound to field units)
─────────────────────────────────────────
  { "type": "broadcast", "payload": <original WS message dict> }

Environment variables (.env or shell export)
────────────────────────────────────────────
  API_BASE_URL       Base URL of FastAPI server  (default: http://127.0.0.1:8000)
  API_TOKEN          Service-account JWT for making API calls on behalf of the bridge
  WS_URL             WebSocket URL to subscribe for broadcasts
                     (default: ws://127.0.0.1:8000/ws/events)
  RNS_APP_NAME       Reticulum destination app name  (default: drd)
  RNS_APP_ASPECT     Reticulum destination aspect     (default: bridge)
  RNS_CONFIG_DIR     Path to directory containing reticulum.config
                     (default: ~/.reticulum)
  BRIDGE_LOG_LEVEL   Logging level: DEBUG / INFO / WARNING  (default: INFO)
"""

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Optional
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

import aiohttp
import msgpack
import RNS

# ── Configuration ─────────────────────────────────────────────────────────────

API_BASE   = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")
API_TOKEN  = os.getenv("API_TOKEN", "")
WS_URL     = os.getenv("WS_URL", "ws://127.0.0.1:8000/ws/events")
APP_NAME   = os.getenv("RNS_APP_NAME", "drd")
APP_ASPECT = os.getenv("RNS_APP_ASPECT", "bridge")
CONFIG_DIR = os.getenv("RNS_CONFIG_DIR", os.path.expanduser("~/.reticulum"))

LOG_LEVEL = getattr(logging, os.getenv("BRIDGE_LOG_LEVEL", "INFO").upper(), logging.INFO)
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("drd.bridge")

# ── Global state ──────────────────────────────────────────────────────────────

# Maps RNS destination hash (hex) → aiohttp session + user context
# so we can send replies back to specific field units
_known_units: dict[str, dict] = {}

# Event loop shared between RNS callbacks and asyncio
_loop: asyncio.AbstractEventLoop | None = None

# ── Reticulum helpers ─────────────────────────────────────────────────────────

def _unpack(raw: bytes) -> Optional[dict]:
    try:
        return msgpack.unpackb(raw, raw=False)
    except Exception:
        try:
            return json.loads(raw)
        except Exception:
            log.warning("Could not decode packet (not msgpack or JSON)")
            return None


def _pack(data: dict) -> bytes:
    return msgpack.packb(data, use_bin_type=True)


def _send_to_unit(destination_hash: str, payload: dict):
    """Send a msgpack packet to a known field-unit destination."""
    try:
        dest_bytes = bytes.fromhex(destination_hash)
        dest = RNS.Destination.recall(dest_bytes)
        if dest is None:
            log.debug("Destination %s not in path table — skipping outbound", destination_hash)
            return
        packet = RNS.Packet(dest, _pack(payload))
        packet.send()
        log.debug("Sent to %s: type=%s", destination_hash[:8], payload.get("type"))
    except Exception as exc:
        log.warning("Failed to send to %s: %s", destination_hash[:8], exc)

# ── API forwarding ────────────────────────────────────────────────────────────

async def _post(session: aiohttp.ClientSession, path: str, body: dict, token: str) -> Optional[dict]:
    url = f"{API_BASE}{path}"
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    try:
        async with session.post(url, json=body, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as r:
            if r.status in (200, 201):
                return await r.json()
            text = await r.text()
            log.warning("API %s → %s: %s", path, r.status, text[:200])
    except Exception as exc:
        log.warning("API call failed (%s): %s", path, exc)
    return None


async def _handle_location(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {
        "user_id":   pkt.get("user_id"),
        "latitude":  pkt.get("latitude"),
        "longitude": pkt.get("longitude"),
        "altitude":  pkt.get("altitude"),
        "speed":     pkt.get("speed"),
        "heading":   pkt.get("heading"),
        "accuracy":  pkt.get("accuracy"),
        "battery_level": pkt.get("battery_level"),
        "recorded_at": pkt.get("recorded_at", datetime.now(timezone.utc).isoformat()),
    }
    result = await _post(session, "/api/v1/locations", body, token)
    if result:
        log.info("Location stored for user %s", pkt.get("user_id", "?")[:8])


async def _handle_sos(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {
        "user_id":    pkt.get("user_id"),
        "event_type": "FLAG",
        "description": pkt.get("message", "SOS via Reticulum mesh"),
        "event_metadata": {
            "source": "reticulum",
            "latitude":  pkt.get("latitude"),
            "longitude": pkt.get("longitude"),
        },
    }
    result = await _post(session, "/api/v1/events", body, token)
    if result:
        log.warning("SOS event created for user %s", pkt.get("user_id", "?")[:8])


async def _handle_message(session: aiohttp.ClientSession, pkt: dict):
    token = pkt.get("token") or API_TOKEN
    body = {
        "sender_id":  pkt.get("user_id"),
        "content":    pkt.get("content", ""),
        "team_id":    pkt.get("team_id"),
        "recipient_id": pkt.get("recipient_id"),
        "msg_type":   pkt.get("msg_type", "text"),
    }
    result = await _post(session, "/api/v1/messages", body, token)
    if result:
        log.info("Message forwarded from %s", pkt.get("user_id", "?")[:8])


async def _dispatch(session: aiohttp.ClientSession, pkt: dict):
    msg_type = pkt.get("type", "")
    if msg_type == "location_update":
        await _handle_location(session, pkt)
    elif msg_type == "sos":
        await _handle_sos(session, pkt)
    elif msg_type == "message":
        await _handle_message(session, pkt)
    elif msg_type == "ping":
        src_hash = pkt.get("_src_hash")
        if src_hash:
            _send_to_unit(src_hash, {"type": "pong", "ts": time.time()})
    else:
        log.debug("Unknown packet type: %s", msg_type)

# ── Reticulum destination ─────────────────────────────────────────────────────

def make_destination(identity: RNS.Identity) -> RNS.Destination:
    dest = RNS.Destination(
        identity,
        RNS.Destination.IN,
        RNS.Destination.SINGLE,
        APP_NAME,
        APP_ASPECT,
    )
    dest.set_proof_strategy(RNS.Destination.PROVE_ALL)
    return dest


def on_packet(message: RNS.Packet):
    """Called by RNS in its own thread — schedule the async dispatch."""
    raw = message.plaintext
    pkt = _unpack(raw)
    if pkt is None:
        return

    # Tag with the sender's destination hash so we can reply
    if message.destination:
        pkt["_src_hash"] = message.destination.hash.hex()
        _known_units.setdefault(pkt["_src_hash"], {})

    log.debug("RNS packet received: type=%s src=%s",
              pkt.get("type"), pkt.get("_src_hash", "")[:8])

    if _loop is not None and not _loop.is_closed():
        asyncio.run_coroutine_threadsafe(_enqueue(pkt), _loop)


_inbound_queue: asyncio.Queue = asyncio.Queue()


async def _enqueue(pkt: dict):
    await _inbound_queue.put(pkt)

# ── WebSocket broadcast subscriber ───────────────────────────────────────────

async def ws_subscriber():
    """Subscribe to FastAPI event WebSocket and relay broadcasts to Reticulum."""
    import websockets

    headers = {"Authorization": f"Bearer {API_TOKEN}"} if API_TOKEN else {}
    url = f"{WS_URL}?token={API_TOKEN}" if API_TOKEN else WS_URL

    while True:
        try:
            async with websockets.connect(url, extra_headers=headers) as ws:
                log.info("WS subscriber connected to %s", WS_URL)
                async for raw in ws:
                    try:
                        data = json.loads(raw)
                    except Exception:
                        continue

                    # Re-broadcast to every known field unit
                    payload = {"type": "broadcast", "payload": data}
                    for dest_hash in list(_known_units.keys()):
                        _send_to_unit(dest_hash, payload)

        except Exception as exc:
            log.warning("WS subscriber error: %s — reconnecting in 5 s", exc)
            await asyncio.sleep(5)

# ── Inbound packet worker ─────────────────────────────────────────────────────

async def packet_worker(session: aiohttp.ClientSession):
    while True:
        pkt = await _inbound_queue.get()
        try:
            await _dispatch(session, pkt)
        except Exception as exc:
            log.error("Dispatch error: %s", exc)
        finally:
            _inbound_queue.task_done()

# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    global _loop
    _loop = asyncio.get_running_loop()

    # Validate config
    if not API_TOKEN:
        log.warning("API_TOKEN not set — forwarded requests will use per-packet tokens only")

    # Start Reticulum with our config
    config_path = os.path.join(CONFIG_DIR, "config")
    if not os.path.isfile(config_path):
        # Copy the bundled config template
        import shutil
        os.makedirs(CONFIG_DIR, exist_ok=True)
        bundled = os.path.join(os.path.dirname(__file__), "reticulum.config")
        shutil.copy(bundled, config_path)
        log.info("Copied default config to %s", config_path)

    rns = RNS.Reticulum(configdir=CONFIG_DIR)
    identity = RNS.Identity()
    dest = make_destination(identity)
    dest.set_packet_callback(on_packet)

    log.info("Bridge destination hash: %s", RNS.prettyhexrep(dest.hash))
    log.info("Listening on app=%s aspect=%s", APP_NAME, APP_ASPECT)

    # HTTP session for API forwarding
    async with aiohttp.ClientSession() as session:
        tasks = [
            asyncio.create_task(packet_worker(session), name="packet-worker"),
            asyncio.create_task(ws_subscriber(), name="ws-subscriber"),
        ]

        stop = asyncio.Event()

        def _shutdown(sig, _):
            log.info("Signal %s received — shutting down", sig)
            stop.set()

        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, _shutdown)

        await stop.wait()
        log.info("Bridge stopping")
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    log.info("Bridge stopped")


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        sys.exit("Python 3.11+ required")
    asyncio.run(main())
