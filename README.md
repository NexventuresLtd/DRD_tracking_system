# DRD Tracking System

A multi-platform tracking and situational awareness system for Military DRD.

This repository contains three main components:

- `Clients/` - Web client built with React, TypeScript, Vite and Leaflet.
- `mobile/` - Cross-platform Flutter mobile app for Android, iOS, and web.
- `Server/` - FastAPI backend with SQLAlchemy, Alembic migrations, WebSockets, and Celery support.

## Objective

Provide an integrated platform for real-time tracking, messaging, event monitoring, and map-driven situational awareness.

The system is designed to support:

- live location updates
- WebSocket event streams
- route and point-of-interest visualization
- evidence management and reporting
- mobile-first situational awareness with offline capability

## Tech Stack

- Web: React 19, TypeScript, Vite, Tailwind CSS, Leaflet, WebSocket
- Mobile: Flutter, Dart, Provider, Flutter Map, geolocator, web_socket_channel
- Backend: FastAPI, Uvicorn, SQLAlchemy, Alembic, Redis, Celery, WebSockets
- Database: PostgreSQL (via asyncpg), GeoAlchemy2, Shapely
- Deployment / tooling: `pnpm`, `flutter`, Python virtual environments, `conda` (optional)

## Folder Structure

- `Clients/` - web application source and build configuration
- `mobile/` - Flutter app, platform support, build scripts, assets, and packages
- `Server/` - API server, database migrations, environment config, and service modules

## Setup

### Prerequisites

- Node.js 18+ or 20+
- `pnpm` or `npm` for the web client
- Flutter 3.x compatible with Dart 3.11
- Python 3.11+
- PostgreSQL database
- Redis if using Celery / pub-sub features
- Optional: `conda` environment for the server run script

### Start the backend server

```bash
cd Server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Or use the provided script:

```bash
cd Server
./run.sh
```

### Start the web client

```bash
cd Clients
pnpm install
pnpm dev
```

Or if you use npm:

```bash
cd Clients
npm install
npm run dev
```

### Start the mobile app

```bash
cd mobile
flutter pub get
flutter run
```

For development builds:

```bash
cd mobile
./build_debug_dev.sh
```

For release builds:

```bash
cd mobile
./build_release_prod.sh
```

## Notes

- The mobile app uses flavor configuration and environment-specific API endpoints.
- The web client connects to the backend with environment variables such as `VITE_API_URL` and `VITE_WS_URL`.

## More Information

- `Clients/README.md` - web frontend specifics
- `mobile/README.md` - Flutter mobile app specifics
- `Server/README.md` - backend API server specifics
