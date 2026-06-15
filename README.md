# Loop

Loop is a local-first iOS MVP for six-second videos. It includes a SwiftUI iOS app and a portable Node server that stores videos on the host machine.

## What Is Implemented

- Real sign-up and sign-in with scrypt-hashed passwords.
- Bearer-token API auth stored in the iOS keychain.
- Vertical short-video feed with For You and Following modes.
- Cloud-streamed promoted video ad breaks every 5-10 feed videos when an ad catalog is configured.
- Cloud-streamed Classic Vine archive videos mixed into the For You feed when a Vine catalog is configured.
- Six-second-only camera recording and upload checks.
- Custom AVFoundation camera with six-second progress, camera flip, library fallback, and filter presets.
- Server-side video duration enforcement for MP4/MOV/M4V metadata.
- Local filesystem video storage on the Mac/server host.
- Cloudinary video storage for uploaded videos by default, with local filesystem fallback only when `LOOP_REQUIRE_CLOUD_VIDEO_STREAMING=0`.
- HTTP range video streaming for local development fallback videos.
- Profiles, avatar uploads, bios, creator search, follows, likes, comments, comments preview, and user loop lists.
- Discover with creators, hashtags, and loop search.
- Inbox with conversations, text messages, loop sharing, activity notifications, and local iOS notifications.
- Custom app icon in the asset catalog.
- iOS-native SwiftUI, SF Fonts, and SF Symbols.

## Quick Start

Start the server:

```bash
cd /Users/elywright/Documents/Loop
LOOP_SECRET="$(openssl rand -hex 32)" npm run server
```

Open the app:

```bash
open /Users/elywright/Documents/Loop/Loop.xcodeproj
```

In Xcode, choose the `Loop` scheme and an iPhone simulator, then run.

The simulator can use the default server URL:

```text
http://127.0.0.1:4000
```

## Physical iPhone Setup

1. Keep the server running on your Mac.
2. Make sure the Mac and iPhone are on the same Wi-Fi.
3. Find your Mac Wi-Fi IP:

```bash
ipconfig getifaddr en0
```

4. On Loop's sign-in screen, open `Advanced` and set the server URL to:

```text
http://YOUR_MAC_IP:4000
```

Example:

```text
http://192.168.1.12:4000
```

If the iPhone cannot connect, allow incoming connections for Node in macOS Firewall settings.

## Server Data

By default, the server stores data here:

```text
/Users/elywright/Documents/Loop/server/data
```

The JSON database is:

```text
server/data/db.json
```

Uploaded videos are:

```text
server/data/videos/
```

Reset local data:

```bash
rm -rf /Users/elywright/Documents/Loop/server/data
```

## Server Environment

The server runs on macOS or Linux with Node 20+ and no npm dependencies.

Useful variables:

```bash
HOST=0.0.0.0
PORT=4000
LOOP_SECRET=replace-with-a-long-random-secret
LOOP_DATA_DIR=/absolute/path/to/loop-data
LOOP_MAX_VIDEO_MB=80
LOOP_REQUIRE_CLOUD_VIDEO_STREAMING=1
LOOP_ADS_MANIFEST_URL=https://res.cloudinary.com/YOUR_CLOUD_NAME/raw/upload/loop_ads.json
LOOP_VINES_MANIFEST_URL=https://res.cloudinary.com/YOUR_CLOUD_NAME/raw/upload/loop_vines.json
LOOP_AUTO_VINES=1
LOOP_AUTO_VINES_LIMIT=24
LOOP_INTERNET_ARCHIVE_VINES_URL=https://archive.org/advancedsearch.php?q=title%3AVine%20AND%20mediatype%3Amovies&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=date&rows=80&page=1&output=json
```

Example:

```bash
HOST=0.0.0.0 PORT=4000 LOOP_DATA_DIR="$HOME/LoopData" LOOP_SECRET="$(openssl rand -hex 32)" npm run server
```

Check server health:

```bash
curl http://127.0.0.1:4000/health
```

## Linux Or Cloud Porting

1. Install Node 20+.
2. Copy the repo to the server.
3. Set `LOOP_SECRET` and `LOOP_DATA_DIR`.
4. Run `npm run server` directly, with `pm2`, or under `systemd`.
5. Put a reverse proxy like Nginx/Caddy in front for HTTPS.
6. Set the app's server URL to the HTTPS domain.

The API uses plain HTTP locally, but production should use HTTPS.

## CLI Build With Xcode Beta

This Mac currently has Command Line Tools selected globally, so CLI builds should point at Xcode beta explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project /Users/elywright/Documents/Loop/Loop.xcodeproj \
  -scheme Loop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## API Map

- `GET /health`
- `POST /api/auth/signup`
- `POST /api/auth/login`
- `GET /api/me`
- `PATCH /api/me`
- `POST /api/me/avatar`
- `GET /api/feed?scope=forYou`
- `GET /api/feed?scope=following`
- `GET /api/discover`
- `GET /api/search?q=username`
- `POST /api/loops`
- `POST /api/loops/:id/like`
- `DELETE /api/loops/:id/like`

## Ad and Vine Cloud Catalogs

Loop monetizes the iOS feed with Google AdMob interstitials. Debug builds use Google's test interstitial unit; release builds use the production unit configured in [AdvertisingService.swift](/Users/elywright/Documents/Loop/Loop/Services/AdvertisingService.swift).

The server can still read optional promoted video cards from `LOOP_ADS_MANIFEST_URL` or, by default, `https://res.cloudinary.com/$CLOUDINARY_CLOUD_NAME/raw/upload/loop_ads.json`. Those direct sponsor cards are separate from AdMob and are only used if you provide a catalog.

Classic Vine archive videos come from `LOOP_VINES_MANIFEST_URL` or `loop_vines.json` in the same Cloudinary account. If that catalog is missing or empty, `LOOP_AUTO_VINES=1` lets the server discover short HTTPS video files from Internet Archive metadata and mix them into the For You feed automatically. Set `LOOP_AUTO_VINES=0` to disable that fallback.

Use [server/loop_ads.example.json](/Users/elywright/Documents/Loop/server/loop_ads.example.json) and [server/loop_vines.example.json](/Users/elywright/Documents/Loop/server/loop_vines.example.json) as templates. Every `videoURL` must be HTTPS so the app streams the video from the cloud.
- `GET /api/loops/:id/comments`
- `POST /api/loops/:id/comments`
- `POST /api/users/:id/follow`
- `DELETE /api/users/:id/follow`
- `GET /api/users/:id`
- `GET /api/users/:id/loops`
- `GET /api/notifications`
- `POST /api/notifications/read`
- `GET /api/conversations`
- `POST /api/conversations`
- `GET /api/conversations/:id/messages`
- `POST /api/conversations/:id/messages`
- `GET /videos/:file`
- `GET /avatars/:file`
