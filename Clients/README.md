# DRD Tracking Web Client

This folder contains the React + TypeScript + Vite web client for the DRD Tracking System.

The client provides map-based tracking, live WebSocket streams, login flows, and dashboard views for operational situational awareness.

## Technologies

- React 19
- TypeScript
- Vite 8
- Tailwind CSS
- Leaflet / React Leaflet
- WebSockets
- Axios

## Getting Started

Install dependencies:

```bash
cd Clients
pnpm install
```

Run in development mode:

```bash
pnpm dev
```

Build for production:

```bash
pnpm build
```

Preview the production build:

```bash
pnpm preview
```

Lint the project:

```bash
pnpm lint
```

## Environment

The client uses environment variables for API and WebSocket endpoints:

- `VITE_API_URL`
- `VITE_WS_URL`

If these are not defined, it falls back to the default deployed production API host.

## Folder structure

- `src/` - application source code
- `src/Pages/` - page components such as `Login` and `DODMap`
- `src/services/` - API and WebSocket connection helpers
- `public/` - static assets

## Notes

See the root `README.md` for repository-level setup info and server integration.
