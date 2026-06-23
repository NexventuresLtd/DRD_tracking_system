#!/usr/bin/env python3
"""
DRD Field Client — runs on a laptop/computer in the field.
Connects to the DRD bridge via Reticulum (UDP/LoRa/TCP) and:
  • streams GPS location (from gpsd or manual input) every N seconds
  • listens for broadcasts from the bridge and prints them
  • sends SOS on Ctrl+C (2 rapid presses)

Usage:
  python field_client.py --bridge <BRIDGE_HASH> --token <JWT> [--lat 0.0 --lng 0.0]
  python field_client.py --bridge <BRIDGE_HASH> --token <JWT> --gpsd

The BRIDGE_HASH is printed by the bridge at startup:
  "Bridge ready  RNS destination : <HASH>"
"""

import argparse
import asyncio
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

import msgpack
import RNS

log = logging.getLogger("drd.field")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

CONFIG_DIR = os.getenv("RNS_CONFIG_DIR", str(Path.home() / ".reticulum"))
IDENTITY_PATH = str(Path.home() / ".reticulum" / "drd_field_identity")


def load_identity() -> RNS.Identity:
    path = Path(IDENTITY_PATH)
    if path.exists():
        return RNS.Identity.from_file(str(path))
    ident = RNS.Identity()
    path.parent.mkdir(parents=True, exist_ok=True)
    ident.to_file(str(path))
    log.info("New field identity saved → %s", path)
    return ident


def pack(d: dict) -> bytes:
    return msgpack.packb(d, use_bin_type=True)


def unpack(b: bytes) -> dict:
    try:
        return msgpack.unpackb(b, raw=False)
    except Exception:
        return json.loads(b)


class FieldClient:
    def __init__(self, bridge_hash: str, token: str, user_id: str):
        self.bridge_hash = bridge_hash
        self.token       = token
        self.user_id     = user_id
        self._dest: RNS.Destination | None = None
        self._sos_pending = False
        self._last_ctrl_c = 0.0

    def _resolve_bridge(self) -> RNS.Destination | None:
        dest_bytes = bytes.fromhex(self.bridge_hash)
        dest_id    = RNS.Identity.recall(dest_bytes)
        if dest_id is None:
            RNS.Transport.request_path(dest_bytes)
            log.info("Requesting path to bridge %s…", self.bridge_hash[:8])
            return None
        dest = RNS.Destination(dest_id, RNS.Destination.OUT, RNS.Destination.SINGLE, "drd", "bridge")
        return dest

    def send(self, payload: dict):
        dest = self._resolve_bridge()
        if dest is None:
            log.warning("Bridge not reachable yet — packet dropped")
            return
        payload["token"]   = self.token
        payload["user_id"] = self.user_id
        pkt = RNS.Packet(dest, pack(payload))
        pkt.send()
        log.debug("Sent: %s", payload.get("type"))

    def send_location(self, lat: float, lng: float, alt: float = 0.0):
        self.send({
            "type":      "location_update",
            "latitude":  lat,
            "longitude": lng,
            "altitude":  alt,
            "recorded_at": datetime.now(timezone.utc).isoformat(),
        })
        log.info("📍 Location sent: %.5f, %.5f", lat, lng)

    def send_sos(self, lat: float | None = None, lng: float | None = None, msg: str = ""):
        payload: dict = {"type": "sos"}
        if lat is not None: payload["latitude"]  = lat
        if lng is not None: payload["longitude"] = lng
        if msg: payload["message"] = msg
        self.send(payload)
        log.warning("🆘 SOS SENT")

    def on_packet(self, pkt: RNS.Packet):
        try:
            data = unpack(pkt.plaintext)
            if data.get("type") == "broadcast":
                inner = data.get("payload", {})
                t = inner.get("type", "")
                if t == "sos_alert":
                    log.warning("🆘 SOS ALERT from %s: %s", inner.get("user_name"), inner.get("message", ""))
                elif t == "new_message":
                    m = inner.get("message", {})
                    log.info("💬 [%s] %s", m.get("channel", "?"), m.get("content", ""))
                elif t == "mission_created":
                    log.info("📋 New mission: %s", inner.get("name", ""))
                else:
                    log.debug("Broadcast: %s", t)
            elif data.get("type") == "pong":
                log.info("🏓 Pong from bridge (latency measured)")
        except Exception as exc:
            log.debug("Packet parse error: %s", exc)


async def _gpsd_location():
    """Pull location from gpsd (localhost:2947) if available."""
    try:
        reader, writer = await asyncio.open_connection("127.0.0.1", 2947)
        writer.write(b'?WATCH={"enable":true,"json":true}\n')
        while True:
            line = await reader.readline()
            try:
                d = json.loads(line)
                if d.get("class") == "TPV" and "lat" in d:
                    return d["lat"], d["lon"], d.get("alt", 0.0)
            except Exception:
                pass
    except Exception:
        return None


async def run(args):
    rns = RNS.Reticulum(configdir=CONFIG_DIR)
    identity = load_identity()

    # Self destination so bridge can reply
    my_dest = RNS.Destination(identity, RNS.Destination.IN, RNS.Destination.SINGLE, "drd", "field")
    my_dest.set_packet_callback(lambda p: client.on_packet(p))

    client = FieldClient(args.bridge, args.token, args.user_id)

    log.info("Field client started. My hash: %s", RNS.prettyhexrep(my_dest.hash))
    log.info("Bridge target: %s", args.bridge[:16])
    log.info("Press Ctrl+C twice rapidly to send SOS")

    lat, lng = args.lat, args.lng
    interval = args.interval

    sos_triggered = False

    def ctrl_c(sig, frame):
        nonlocal sos_triggered
        now = time.time()
        if now - ctrl_c.last < 2.0:
            client.send_sos(lat, lng, "EMERGENCY — field operator triggered SOS")
            sos_triggered = True
        ctrl_c.last = now
    ctrl_c.last = 0.0

    import signal as _signal
    _signal.signal(_signal.SIGINT, ctrl_c)

    while not sos_triggered:
        if args.gpsd:
            result = await _gpsd_location()
            if result:
                lat, lng, alt = result
                client.send_location(lat, lng, alt)
            else:
                log.warning("gpsd unavailable — using manual coords")
                if lat is not None and lng is not None:
                    client.send_location(lat, lng)
        elif lat is not None and lng is not None:
            client.send_location(lat, lng)

        # Send a ping every 10 intervals to measure latency
        if int(time.time()) % (interval * 10) < interval:
            client.send({"type": "ping"})

        await asyncio.sleep(interval)

    log.info("Field client stopped.")


def main():
    p = argparse.ArgumentParser(description="DRD Field Client")
    p.add_argument("--bridge",   required=True, help="Bridge RNS destination hash")
    p.add_argument("--token",    default=os.getenv("API_TOKEN", ""), help="JWT token")
    p.add_argument("--user-id",  default=os.getenv("DRD_USER_ID", ""), dest="user_id")
    p.add_argument("--lat",      type=float, default=None)
    p.add_argument("--lng",      type=float, default=None)
    p.add_argument("--gpsd",     action="store_true", help="Use gpsd for live GPS")
    p.add_argument("--interval", type=int, default=10, help="Location update interval (s)")
    args = p.parse_args()

    if not args.token:
        p.error("--token or API_TOKEN env var required")
    if not args.user_id:
        p.error("--user-id or DRD_USER_ID env var required")
    if not args.gpsd and (args.lat is None or args.lng is None):
        p.error("Provide --lat/--lng or use --gpsd")

    asyncio.run(run(args))


if __name__ == "__main__":
    main()
