# How to Host Your Loop Server & Videos in the Cloud (Free Forever)

This guide details how to host your Loop Node.js backend server and video assets in the cloud completely for free, with persistent database storage, zero-configuration media hosting, and dynamic client URL syncing.

---

## Architecture Overview

Free cloud hosting providers (like Render) use **ephemeral containers**, meaning any files stored on their local disks (including local databases and uploaded videos) are wiped when the server sleeps or restarts.

To solve this, this codebase implements:
1. **Cloud Media Storage**: All recorded videos and user avatars are uploaded directly to **Cloudinary** via secure server-side Basic Authentication.
2. **Encrypted Cloud Database**: The database file (`db.json`) is symmetrically encrypted on the server using AES-256-CBC (powered by your `LOOP_SECRET`) and saved securely to your Cloudinary account. On server startup, it is automatically downloaded, decrypted, and restored in memory.
3. **Dynamic URL Resolution**: When the server starts up on Render, it automatically detects its public URL and publishes it to Cloudinary. The iOS app fetches this URL on launch, meaning you **never** have to copy-paste URLs or rebuild the app when the server restarts or sleeps!
4. **Cloud Feed Catalogs**: Optional promoted video cards and Classic Vine archive videos are read from HTTPS JSON manifests in Cloudinary, then mixed into the For You feed as cloud-streamed video cards. If no Vine manifest exists, the server can automatically discover short cloud-hosted Vine-style clips from Internet Archive metadata.

---

## Cloudinary Credentials

The server is configured to use your Cloudinary credentials out of the box:
- **Cloud Name**: `dvfindvne`
- **API Key**: `121998653439447`
- **API Secret**: `3vFMmWI1huqi-FavGNfzbH54aQw`

*(If you ever want to change these, simply set the `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET` environment variables on Render.)*

---

## Deploy for Free on Render (No Credit Card Required)

Render is a premium cloud host. Its free web service tier does **not** require a credit card to sign up or deploy. It sleeps after 15 minutes of inactivity, but wakes up automatically when a request arrives.

1. **Push your code**: Push the root directory of this codebase to a private/public GitHub repository.
2. **Sign up**: Create a free account at [Render](https://render.com) (no credit card needed).
3. **Create a Web Service**:
   - Click **New +** -> **Web Service**.
   - Connect your GitHub repository.
4. **Configure deployment**:
   - **Environment**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `npm run server`
   - **Instance Type**: Select **Free** (very important, so it does not ask for billing info).
5. **Add Environment Variables** (under the "Environment" tab):
   - `LOOP_SECRET`: A secure, random string (e.g., `my-super-secret-key-123`). This is used to encrypt your database backups.
   - `LOOP_REQUIRE_CLOUD_VIDEO_STREAMING`: Keep this as `1` or leave it unset so new uploads fail instead of falling back to ephemeral local storage.
   - `LOOP_ADS_MANIFEST_URL`: Optional custom HTTPS URL for your promoted-video ad catalog.
   - `LOOP_VINES_MANIFEST_URL`: Optional custom HTTPS URL for your Classic Vine archive catalog.
   - `LOOP_AUTO_VINES`: Keep this as `1` or leave it unset to auto-fill Classic Vine cards from Internet Archive when your Vine catalog is missing. Set it to `0` to disable the fallback.
   - `LOOP_AUTO_VINES_LIMIT`: Optional max number of auto-discovered Vine cards to cache per refresh. Defaults to `24`.
6. **Done**: Render will build and deploy the server. Render automatically sets `RENDER_EXTERNAL_URL`, which the server detects and publishes to Cloudinary.

## Promoted Video Ads

Google AdMob interstitials are integrated directly in the iOS app, so Google fills paid ads automatically. Debug builds use Google's test ad unit, and release builds use the production ad unit in `Loop/Services/AdvertisingService.swift`.

The server-side promoted-video catalog remains optional for direct sponsor clips. Upload a JSON file like `server/loop_ads.example.json` to Cloudinary as `loop_ads.json`, or set `LOOP_ADS_MANIFEST_URL` to any HTTPS JSON URL. Each ad entry needs a cloud `videoURL`, a `sponsorName`, a `provider`, and an optional `callToActionURL`.

## Classic Vine Archive

Upload a JSON file like `server/loop_vines.example.json` to Cloudinary as `loop_vines.json`, or set `LOOP_VINES_MANIFEST_URL`, when you want a curated archive. Only include Vine videos you have rights to redistribute.

If that manifest is missing or empty, `LOOP_AUTO_VINES=1` makes the server query Internet Archive metadata, choose short HTTPS video files, and render them as read-only Classic Vine cards mixed into the For You feed. All Vine and UGC videos must resolve to HTTPS video URLs so the app streams them from the cloud.
