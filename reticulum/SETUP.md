# DRD Reticulum Mesh Setup

## Architecture

```
Android/iOS phone            Laptop / computer           DRD Server
(Sideband app)               (field_client.py)           (FastAPI)
      │                              │                       │
      │   LXMF over UDP/WiFi/LoRa   │  msgpack over RNS     │
      └──────────────────────────────┴───────────────────────┤
                                                         bridge.py
                                                     (this process)
```

The bridge runs on any machine with both:
- A network route to the DRD FastAPI server (internet or LAN)
- A Reticulum interface to the field network (WiFi UDP, LoRa, TCP)

---

## 1 — Bridge Setup (server-side computer)

```bash
cd reticulum/
cp .env.example .env
# Edit .env: set API_BASE_URL, API_TOKEN

./start_bridge.sh
# First run prints:
#   Bridge ready
#     RNS  destination : <HASH>   ← give this to field units
#     LXMF destination : <HASH>   ← add this in Sideband
```

The bridge identity is saved to `RNS_IDENTITY_PATH` so the hash never changes across restarts.

---

## 2 — Android/iOS Phones (Sideband)

**Install:**
- Android: [Sideband on F-Droid or Google Play](https://github.com/markqvist/Sideband)
- iOS: TestFlight (search "Sideband RNS")

**Connect to bridge:**
1. Open Sideband → Conversations → New → Add contact by hash
2. Paste the **LXMF destination hash** printed by the bridge
3. Name it "DRD Command"
4. Ensure both devices are on the same WiFi network (or LoRa network)

**Send commands (as JSON in the message body):**
```json
{"type":"sos","message":"Contact at grid 4B"}
{"type":"message","content":"Moving to waypoint 3","channel":"global"}
{"type":"location_update","latitude":-1.9441,"longitude":30.0619}
{"type":"ping"}
```

Plain text messages (not starting with `{`) are forwarded to the global chat channel.

**Receive broadcasts:**
Broadcasts from the DRD server (SOS alerts, mission updates, etc.) arrive as LXMF messages from the bridge.

---

## 3 — Computers / Laptops (field_client.py)

**Install:**
```bash
cd reticulum/
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

**Run with manual coordinates:**
```bash
python field_client.py \
  --bridge <RNS_DESTINATION_HASH> \
  --token  <YOUR_JWT_TOKEN> \
  --user-id <YOUR_USER_UUID> \
  --lat -1.9441 --lng 30.0619 \
  --interval 10
```

**Run with live GPS (gpsd):**
```bash
# Install gpsd and connect a USB GPS receiver
sudo apt install gpsd gpsd-clients
gpsd /dev/ttyUSB0

python field_client.py --bridge <HASH> --token <TOKEN> --user-id <UUID> --gpsd
```

**Send SOS:** Press `Ctrl+C` twice within 2 seconds.

---

## 4 — Reticulum Interfaces

Edit `~/.reticulum/config` (or the file at `RNS_CONFIG_DIR/config`):

### Same WiFi network (development / base camp)
Already enabled by default — UDP broadcast on port 4242.

### LoRa radios (RNODE hardware — field deployment)
```ini
[[LoRa Radio]]
  type            = RNodeInterface
  enabled         = true
  port            = /dev/ttyUSB0    # adjust for your hardware
  frequency       = 868000000       # 868 MHz Europe / 915 MHz Americas
  bandwidth       = 125000
  txpower         = 7
  spreadingfactor = 8
  codingrate      = 5
```

### Connect to a remote Reticulum hub (via internet)
```ini
[[Hub]]
  type        = TCPClientInterface
  enabled     = true
  target_host = your-hub.example.com
  target_port = 4242
```

### Phone hotspot (phone creates WiFi hotspot, computer connects)
No config change needed — the UDP interface discovers peers automatically.

---

## 5 — Verify connectivity

```bash
# On the bridge machine:
python -c "import RNS; r=RNS.Reticulum(); print('RNS OK')"

# Check the bridge can reach the server:
curl http://127.0.0.1:8000/health

# From a field client — send a ping:
python field_client.py --bridge <HASH> --token <TOKEN> --user-id <UUID> \
  --lat 0 --lng 0 --interval 9999
# You should see: 🏓 Pong from bridge
```

---

## 6 — Offline operation

If the bridge loses internet connectivity:
- Reticulum mesh between field units continues working
- location and message packets queue on the bridge
- When connectivity restores, they are forwarded to the API

If a field computer runs `field_client.py` without a bridge:
- Packets are queued in Reticulum's transport layer
- Delivered when a path to the bridge becomes available

The Flutter mobile app has its own offline queue (SQLite) that flushes automatically when the device regains connectivity.
