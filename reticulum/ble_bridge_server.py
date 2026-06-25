#!/usr/bin/env python3
"""
DRD BLE Bridge Server  (bidirectional)
=======================================
Laptop runs as a BLE GATT peripheral.

Phone → Laptop  (RX char, write):   chat / location / SOS  → forwarded to FastAPI
Laptop → Phone  (TX char, notify):  FastAPI WS events       → pushed to all phones

"""

import asyncio
import json
import logging
import os
import signal
import sys
from typing import Any

try:
    from bless import (
        BlessServer,
        BlessGATTCharacteristic,
        GATTCharacteristicProperties,
        GATTAttributePermissions,
    )
except ImportError:
    sys.exit("Missing: pip install bless")

try:
    import aiohttp
    import websockets
except ImportError:
    sys.exit("Missing: pip install aiohttp websockets")

# ── Config ────────────────────────────────────────────────────────────────────

API_BASE  = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")
API_TOKEN = os.getenv("API_TOKEN", "")
WS_URL    = os.getenv("WS_URL", f"ws://127.0.0.1:8000/ws/events")

# Same UUIDs as Flutter BleService — phones discover by service UUID
SERVICE_UUID = "6d726400-0000-1000-8000-000000000001"
RX_CHAR_UUID = "6d726401-0000-1000-8000-000000000001"  # phone → laptop (write)
TX_CHAR_UUID = "6d726402-0000-1000-8000-000000000001"  # laptop → phone (notify)

DEVICE_NAME  = "DRD-BRIDGE"
BLE_MTU      = 500   # safe chunk size for BLE notify

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s]  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("drd.ble")

# ── Globals ───────────────────────────────────────────────────────────────────

_bufs: dict[str, str] = {}          # partial-line buffers per phone connection
_session: aiohttp.ClientSession | None = None
_server:  BlessServer | None        = None

# ── Phone → Laptop (GATT write callbacks) ────────────────────────────────────

def on_read(characteristic: BlessGATTCharacteristic, **kwargs: Any) -> bytearray:
    return characteristic.value or bytearray()

def on_write(characteristic: BlessGATTCharacteristic, value: bytearray, **kwargs: Any) -> None:
    if characteristic.uuid.lower() != RX_CHAR_UUID.lower():
        return

    device_id = str(kwargs.get("connection_id", "phone"))
    chunk = value.decode("utf-8", errors="ignore")
    _bufs.setdefault(device_id, "")
    _bufs[device_id] += chunk

    while "\n" in _bufs[device_id]:
        line, _bufs[device_id] = _bufs[device_id].split("\n", 1)
        line = line.strip()
        if not line:
            continue
        try:
            pkt = json.loads(line)
            asyncio.get_event_loop().call_soon_threadsafe(
                lambda p=pkt: asyncio.ensure_future(_dispatch(p))
            )
        except json.JSONDecodeError:
            log.warning("Bad JSON from %s: %.80s", device_id, line)

# ── Dispatch phone packet → FastAPI ──────────────────────────────────────────

async def _post(path: str, body: dict, user_token: str | None = None) -> int:
    if _session is None:
        return 0
    token = user_token or API_TOKEN
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    }
    try:
        async with _session.post(
            f"{API_BASE}/api/v1{path}", json=body, headers=headers,
            timeout=aiohttp.ClientTimeout(total=8),
        ) as r:
            return r.status
    except Exception as exc:
        log.warning("API call failed %s: %s", path, exc)
        return 0

async def _dispatch(pkt: dict) -> None:
    t = pkt.get("type", "")
    # Use the user's own JWT if the phone included it; fall back to service token
    user_token: str | None = pkt.get("token")
    log.info("Phone→Bridge  type=%-10s  auth=%s", t, "user" if user_token else "service")

    if t == "message":
        status = await _post("/messages", {
            "content": pkt.get("content", ""),
            "channel": pkt.get("channel", "global"),
        }, user_token)
        log.info("  Chat → FastAPI HTTP %d", status)

    elif t == "location":
        body = {k: pkt[k] for k in
                ("latitude", "longitude", "altitude", "speed", "heading", "accuracy")
                if k in pkt}
        body.setdefault("recorded_at", pkt.get("recorded_at", ""))
        status = await _post("/locations", body, user_token)
        log.info("  Location → FastAPI HTTP %d", status)

    elif t == "sos":
        body = {k: pkt[k] for k in ("latitude", "longitude", "message") if k in pkt}
        body.setdefault("message", "SOS via BLE bridge")
        status = await _post("/sos", body, user_token)
        log.warning("  SOS → FastAPI HTTP %d", status)

    else:
        log.debug("  Unknown type: %s", t)

# ── Laptop → Phone (BLE notify) ───────────────────────────────────────────────

async def _notify_phones(data: dict) -> None:
    """Push a server event to all BLE-connected phones via TX characteristic notify."""
    if _server is None:
        return
    try:
        encoded = (json.dumps(data, separators=(",", ":")) + "\n").encode()
        # Send in MTU-sized chunks
        for i in range(0, len(encoded), BLE_MTU):
            chunk = bytearray(encoded[i : i + BLE_MTU])
            _server.get_characteristic(TX_CHAR_UUID).value = chunk
            _server.update_value(SERVICE_UUID, TX_CHAR_UUID)
            if len(encoded) > BLE_MTU:
                await asyncio.sleep(0.05)   # brief pause between chunks
    except Exception as exc:
        log.warning("BLE notify failed: %s", exc)

# ── FastAPI WebSocket subscriber ──────────────────────────────────────────────

async def _ws_subscriber() -> None:
    """
    Subscribes to FastAPI's event stream and forwards every event to all
    BLE-connected phones via the TX characteristic notify.
    Reconnects automatically on disconnect.
    """
    url = f"{WS_URL}?token={API_TOKEN}" if API_TOKEN else WS_URL
    while True:
        try:
            async with websockets.connect(url) as ws:
                log.info("WS connected to FastAPI event stream")
                async for raw in ws:
                    try:
                        data = json.loads(raw)
                        event_type = data.get("type", data.get("event", "?"))
                        await _notify_phones(data)
                        log.info("Bridge→Phone  type=%-10s  via BLE notify", event_type)
                    except Exception as exc:
                        log.warning("WS event parse error: %s", exc)
        except Exception as exc:
            log.warning("WS disconnected (%s) — retry in 5 s", exc)
            await asyncio.sleep(5)

# ── Main ──────────────────────────────────────────────────────────────────────

async def main() -> None:
    global _session, _server

    _session = aiohttp.ClientSession()

    loop = asyncio.get_running_loop()
    _server = BlessServer(name=DEVICE_NAME, loop=loop)
    _server.read_request_func  = on_read
    _server.write_request_func = on_write

    # Register DRD GATT service
    await _server.add_new_service(SERVICE_UUID)

    # RX characteristic — phone writes here
    await _server.add_new_characteristic(
        SERVICE_UUID, RX_CHAR_UUID,
        GATTCharacteristicProperties.write | GATTCharacteristicProperties.write_without_response,
        None,
        GATTAttributePermissions.writeable,
    )

    # TX characteristic — laptop notifies phone here
    await _server.add_new_characteristic(
        SERVICE_UUID, TX_CHAR_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.notify,
        bytearray(b"DRD-BRIDGE-READY"),
        GATTAttributePermissions.readable,
    )

    await _server.start()

    log.info("=" * 60)
    log.info("  DRD BLE Bridge  —  bidirectional")
    log.info("  Advertising as : %s", DEVICE_NAME)
    log.info("  Service UUID   : %s", SERVICE_UUID)
    log.info("  API endpoint   : %s", API_BASE)
    log.info("  WS events      : %s", WS_URL)
    log.info("")
    log.info("  Phone→Bridge   : chat / location / SOS  (BLE write)")
    log.info("  Bridge→Phone   : all FastAPI events      (BLE notify)")
    log.info("=" * 60)

    stop = asyncio.Event()

    def _on_signal(*_: Any) -> None:
        stop.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _on_signal)

    # Run WS subscriber alongside the BLE server
    ws_task = asyncio.create_task(_ws_subscriber(), name="ws-subscriber")

    await stop.wait()

    log.info("Shutting down…")
    ws_task.cancel()
    await asyncio.gather(ws_task, return_exceptions=True)
    await _server.stop()
    await _session.close()
    log.info("BLE bridge stopped.")


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        sys.exit("Python 3.11+ required")
    asyncio.run(main())
