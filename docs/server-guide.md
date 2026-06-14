# Loop Server Guide

Loop's server is intentionally small and portable. It uses Node's standard library, stores videos on disk, and keeps MVP data in a JSON database.

## Start On This Mac

```bash
cd /Users/elywright/Documents/Loop
LOOP_SECRET="$(openssl rand -hex 32)" npm run server
```

Expected output:

```text
[loop] server listening on http://0.0.0.0:4000
[loop] storing videos and db in /Users/elywright/Documents/Loop/server/data
```

## Connect From The iOS Simulator

Use:

```text
http://127.0.0.1:4000
```

That is the app's default server URL.

## Connect From A Real iPhone

Find the Mac's Wi-Fi address:

```bash
ipconfig getifaddr en0
```

Use that address in the app:

```text
http://YOUR_MAC_IP:4000
```

Keep both devices on the same Wi-Fi. If macOS asks about incoming network access for Node, allow it.

## Storage

Default:

```text
server/data/db.json
server/data/videos/
server/data/avatars/
```

Custom storage path:

```bash
LOOP_DATA_DIR="$HOME/LoopData" LOOP_SECRET="$(openssl rand -hex 32)" npm run server
```

## Six-Second Enforcement

The app checks duration before upload.

The server also reads MP4/MOV/M4V duration metadata and rejects videos over six seconds plus a small encoding tolerance.

## Cloud Notes

For Linux/cloud:

```bash
HOST=0.0.0.0 PORT=4000 LOOP_DATA_DIR=/var/lib/loop LOOP_SECRET=your-long-secret npm run server
```

Run it behind HTTPS before real users connect. When behind a reverse proxy, pass `X-Forwarded-Proto: https` so video URLs are generated with the right scheme.

## Notifications And Messaging

The server stores notification rows for likes, comments, follows, mentions, and messages. The iOS app asks for local notification permission from Inbox, then schedules local notifications from the server activity feed.

Messages are first-party server records:

```text
GET /api/conversations
POST /api/conversations
GET /api/conversations/:id/messages
POST /api/conversations/:id/messages
```

Loop attachments in messages reference existing posted loops by `loopId`.
