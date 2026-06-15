# How to Host Your Loop Server & Videos in the Cloud (Free Forever)

This guide details how to host your Loop Node.js backend server and video assets in the cloud completely for free, with persistent database storage, zero-configuration media hosting, and dynamic client URL syncing.

---

## Architecture Overview

Free cloud hosting providers (like Render) use **ephemeral containers**, meaning any files stored on their local disks (including local databases and uploaded videos) are wiped when the server sleeps or restarts.

To solve this, this codebase implements:
1. **Cloud Media Storage**: All recorded videos and user avatars are uploaded directly to **Cloudinary** via secure server-side Basic Authentication.
2. **Encrypted Cloud Database**: The database file (`db.json`) is symmetrically encrypted on the server using AES-256-CBC (powered by your `LOOP_SECRET`) and saved securely to your Cloudinary account. On server startup, it is automatically downloaded, decrypted, and restored in memory.
3. **Dynamic URL Resolution**: When the server starts up on Render, it automatically detects its public URL and publishes it to Cloudinary. The iOS app fetches this URL on launch, meaning you **never** have to copy-paste URLs or rebuild the app when the server restarts or sleeps!
4. **Cloud Feed Catalogs**: Promoted video ads and Classic Vine archive videos are read from HTTPS JSON manifests in Cloudinary, then mixed into the For You feed as cloud-streamed video cards.

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
6. **Done**: Render will build and deploy the server. Render automatically sets `RENDER_EXTERNAL_URL`, which the server detects and publishes to Cloudinary.

## Promoted Video Ads

Upload a JSON file like `server/loop_ads.example.json` to Cloudinary as `loop_ads.json`, or set `LOOP_ADS_MANIFEST_URL` to any HTTPS JSON URL. Each ad entry needs a cloud `videoURL`, a `sponsorName`, a `provider` such as `google`, `apple`, or `direct`, and an optional `callToActionURL`.

The app labels these feed items as ads and the server inserts one after a randomized 5-10 normal feed videos. Use `provider: "google"`, `provider: "apple"`, or `provider: "direct"` in the ad catalog to track where each promoted video came from without making Xcode depend on an ad SDK package during ordinary builds.

## Classic Vine Archive

Upload a JSON file like `server/loop_vines.example.json` to Cloudinary as `loop_vines.json`, or set `LOOP_VINES_MANIFEST_URL`. Only include Vine videos you have rights to redistribute. The server accepts only HTTPS video URLs, and the app renders these as read-only Classic Vine cards mixed into the For You feed.
