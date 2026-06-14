#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const https = require("node:https");
const path = require("node:path");
const { URL } = require("node:url");

const HOST = process.env.HOST || "0.0.0.0";
const PORT = Number(process.env.PORT || 4000);
const DATA_DIR = process.env.LOOP_DATA_DIR
  ? path.resolve(process.env.LOOP_DATA_DIR)
  : path.join(__dirname, "data");
const VIDEO_DIR = path.join(DATA_DIR, "videos");
const AVATAR_DIR = path.join(DATA_DIR, "avatars");
const DB_PATH = path.join(DATA_DIR, "db.json");
const MAX_VIDEO_BYTES = Number(process.env.LOOP_MAX_VIDEO_MB || 80) * 1024 * 1024;
const MAX_DURATION_SECONDS = 60;
const DURATION_TOLERANCE_SECONDS = 0.25;
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;
const SECRET = process.env.LOOP_SECRET || "loop-local-dev-secret-change-me";

if (!process.env.LOOP_SECRET) {
  console.warn("[loop] LOOP_SECRET is not set; using the local development secret.");
}

// Cloudinary Credentials & Configuration
const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || "dvfindvne";
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || "121998653439447";
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || "3vFMmWI1huqi-FavGNfzbH54aQw";
const CLOUDINARY_AUTH = "Basic " + Buffer.from(CLOUDINARY_API_KEY + ":" + CLOUDINARY_API_SECRET).toString("base64");

// AES-256-CBC Encryption Helpers
function encrypt(text, secret) {
  const key = crypto.createHash("sha256").update(secret).digest();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");
  return iv.toString("hex") + ":" + encrypted;
}

function decrypt(text, secret) {
  try {
    const parts = text.split(":");
    if (parts.length < 2) return null;
    const iv = Buffer.from(parts.shift(), "hex");
    const encryptedText = Buffer.from(parts.join(":"), "hex");
    const key = crypto.createHash("sha256").update(secret).digest();
    const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);
    let decrypted = decipher.update(encryptedText, "hex", "utf8");
    decrypted += decipher.final("utf8");
    return decrypted;
  } catch (e) {
    console.error("[loop] decrypt error:", e.message);
    return null;
  }
}

// Simple Helper to fetch text content from a URL via HTTPS
function fetchURL(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP status ${res.statusCode}`));
      }
      let body = "";
      res.on("data", (chunk) => body += chunk);
      res.on("end", () => resolve(body));
    }).on("error", (e) => reject(e));
  });
}

function uploadToCloudinary(fileBuffer, ext) {
  return new Promise((resolve) => {
    if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
      console.warn("[loop] Cloudinary credentials not fully configured; skipping media upload.");
      return resolve(null);
    }
    
    const resourceType = ext === ".jpg" || ext === ".jpeg" || ext === ".png" || ext === ".webp" ? "image" : "video";
    const base64Data = fileBuffer.toString("base64");
    
    let mimeType = `${resourceType}/${ext.replace(".", "")}`;
    if (ext === ".jpg" || ext === ".jpeg") mimeType = "image/jpeg";
    else if (ext === ".mov") mimeType = "video/quicktime";
    else if (ext === ".mp4") mimeType = "video/mp4";
    
    const dataUrl = `data:${mimeType};base64,${base64Data}`;
    
    const postData = JSON.stringify({
      file: dataUrl,
      folder: "loop_media"
    });
    
    const options = {
      hostname: "api.cloudinary.com",
      port: 443,
      path: `/v1_1/${CLOUDINARY_CLOUD_NAME}/${resourceType}/upload`,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(postData),
        "Authorization": CLOUDINARY_AUTH
      }
    };
    
    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk) => body += chunk);
      res.on("end", () => {
        try {
          const json = JSON.parse(body);
          if (json.secure_url) {
            resolve(json.secure_url);
          } else {
            console.error("[Cloudinary Error]", json.error?.message || json);
            resolve(null);
          }
        } catch (e) {
          console.error("[Cloudinary Parse Error]", e);
          resolve(null);
        }
      });
    });
    
    req.on("error", (e) => {
      console.error("[Cloudinary Network Error]", e);
      resolve(null);
    });
    
    req.write(postData);
    req.end();
  });
}

fs.mkdirSync(VIDEO_DIR, { recursive: true });
fs.mkdirSync(AVATAR_DIR, { recursive: true });

const emptyDB = () => ({
  users: [],
  loops: [],
  comments: [],
  likes: [],
  follows: [],
  conversations: [],
  messages: [],
  notifications: []
});

let db = emptyDB(); // Will be populated asynchronously on startup

async function loadDB() {
  // 1. Try to load from Cloudinary first
  if (CLOUDINARY_CLOUD_NAME && SECRET && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET) {
    const url = `https://res.cloudinary.com/${CLOUDINARY_CLOUD_NAME}/raw/upload/loop_db.json?t=${Date.now()}`;
    console.log(`[loop] attempting to load database from Cloudinary: ${url}`);
    
    try {
      const encryptedData = await fetchURL(url);
      if (encryptedData) {
        const decrypted = decrypt(encryptedData, SECRET);
        if (decrypted) {
          const parsed = JSON.parse(decrypted);
          console.log("[loop] successfully loaded and decrypted database from Cloudinary!");
          // Save a local cache copy
          fs.mkdirSync(DATA_DIR, { recursive: true });
          fs.writeFileSync(DB_PATH, JSON.stringify(parsed, null, 2));
          return parsed;
        }
      }
    } catch (e) {
      console.warn("[loop] could not load database from Cloudinary (might not exist yet):", e.message);
    }
  }
  
  // 2. Fallback to local db.json
  console.log("[loop] checking local db.json backup...");
  if (fs.existsSync(DB_PATH)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(DB_PATH, "utf8"));
      return { ...emptyDB(), ...parsed };
    } catch (error) {
      console.error("[loop] failed to read local db.json:", error);
    }
  }
  
  return emptyDB();
}

function saveDB() {
  // Save local backup synchronously
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    const tempPath = `${DB_PATH}.tmp`;
    fs.writeFileSync(tempPath, JSON.stringify(db, null, 2));
    fs.renameSync(tempPath, DB_PATH);
  } catch (err) {
    console.error("[loop] failed to save local db.json:", err);
  }
  
  // Encrypt and upload database backup to Cloudinary in the background
  if (CLOUDINARY_CLOUD_NAME && SECRET && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET) {
    try {
      const dbStr = JSON.stringify(db);
      const encrypted = encrypt(dbStr, SECRET);
      const base64Data = Buffer.from(encrypted).toString("base64");
      const dataUrl = `data:text/plain;base64,${base64Data}`;
      
      const postData = JSON.stringify({
        file: dataUrl,
        public_id: "loop_db.json",
        invalidate: true
      });
      
      const options = {
        hostname: "api.cloudinary.com",
        port: 443,
        path: `/v1_1/${CLOUDINARY_CLOUD_NAME}/raw/upload`,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(postData),
          "Authorization": CLOUDINARY_AUTH
        }
      };
      
      const req = https.request(options, (res) => {
        let body = "";
        res.on("data", (chunk) => body += chunk);
        res.on("end", () => {
          try {
            const json = JSON.parse(body);
            if (json.secure_url) {
              console.log("[loop] database backup saved securely to Cloudinary!");
            } else {
              console.error("[loop] Cloudinary database save error:", json.error?.message || json);
            }
          } catch (e) {
            console.error("[loop] Cloudinary database save parse error:", e);
          }
        });
      });
      
      req.on("error", (e) => {
        console.error("[loop] Cloudinary database save network error:", e);
      });
      
      req.write(postData);
      req.end();
    } catch (e) {
      console.error("[loop] failed to prepare Cloudinary database upload:", e);
    }
  }
}

function nowISO() {
  return new Date().toISOString();
}

function makeId(prefix) {
  return `${prefix}_${crypto.randomBytes(12).toString("hex")}`;
}

function sendJSON(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS"
  });
  res.end(body);
}

function sendError(res, status, message, details) {
  sendJSON(res, status, { error: message, details });
}

function absoluteURL(req, pathname) {
  const proto = req.headers["x-forwarded-proto"] || "http";
  return `${proto}://${req.headers.host}${pathname}`;
}

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function normalizeUsername(username) {
  return String(username || "").trim().replace(/^@/, "").toLowerCase();
}

function assertEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function assertUsername(username) {
  return /^[a-z0-9_]{3,24}$/.test(username);
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("base64url");
  const hash = crypto.scryptSync(String(password), salt, 64).toString("base64url");
  return `scrypt$${salt}$${hash}`;
}

function verifyPassword(password, stored) {
  const [scheme, salt, expected] = String(stored || "").split("$");
  if (scheme !== "scrypt" || !salt || !expected) {
    return false;
  }
  const actual = crypto.scryptSync(String(password), salt, 64);
  const expectedBuffer = Buffer.from(expected, "base64url");
  return expectedBuffer.length === actual.length && crypto.timingSafeEqual(expectedBuffer, actual);
}

function signToken(userId) {
  const payload = {
    sub: userId,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS
  };
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.createHmac("sha256", SECRET).update(encoded).digest("base64url");
  return `${encoded}.${signature}`;
}

function verifyToken(token) {
  const [encoded, signature] = String(token || "").split(".");
  if (!encoded || !signature) {
    return null;
  }
  const expected = crypto.createHmac("sha256", SECRET).update(encoded).digest("base64url");
  const expectedBuffer = Buffer.from(expected);
  const signatureBuffer = Buffer.from(signature);
  if (expectedBuffer.length !== signatureBuffer.length || !crypto.timingSafeEqual(expectedBuffer, signatureBuffer)) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    if (!payload.sub || payload.exp < Math.floor(Date.now() / 1000)) {
      return null;
    }
    return payload;
  } catch {
    return null;
  }
}

function getBearerUser(req, required = true) {
  const header = req.headers.authorization || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    if (required) {
      const error = new Error("Missing bearer token.");
      error.status = 401;
      throw error;
    }
    return null;
  }
  const payload = verifyToken(match[1]);
  const user = payload ? db.users.find((candidate) => candidate.id === payload.sub) : null;
  if (!user) {
    const error = new Error("Invalid or expired token.");
    error.status = 401;
    throw error;
  }
  return user;
}

function publicUser(user, viewerId, req) {
  if (!user) {
    return null;
  }
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    bio: user.bio || "",
    avatarColor: user.avatarColor,
    avatarURL: user.avatarURL || (user.avatarFileName && req ? absoluteURL(req, `/avatars/${encodeURIComponent(user.avatarFileName)}`) : null),
    createdAt: user.createdAt,
    followerCount: db.follows.filter((follow) => follow.followingId === user.id).length,
    followingCount: db.follows.filter((follow) => follow.followerId === user.id).length,
    loopCount: db.loops.filter((loop) => loop.creatorId === user.id).length,
    isFollowedByViewer: Boolean(
      viewerId && db.follows.some((follow) => follow.followerId === viewerId && follow.followingId === user.id)
    )
  };
}

function previewComments(loopId) {
  return db.comments
    .filter((comment) => comment.loopId === loopId)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    .slice(-3)
    .map((comment) => ({
      id: comment.id,
      body: comment.body,
      createdAt: comment.createdAt,
      author: publicUser(db.users.find((user) => user.id === comment.userId))
    }));
}

function formatLoop(req, loop, viewerId) {
  const creator = db.users.find((user) => user.id === loop.creatorId);
  return {
    id: loop.id,
    caption: loop.caption,
    durationSeconds: loop.durationSeconds,
    category: loop.category || (loop.durationSeconds <= 6.25 ? "6s" : "60s"),
    videoURL: loop.videoURL || absoluteURL(req, `/videos/${encodeURIComponent(loop.videoFileName)}`),
    thumbnailURL: null,
    createdAt: loop.createdAt,
    creator: publicUser(creator, viewerId, req),
    likeCount: db.likes.filter((like) => like.loopId === loop.id).length,
    commentCount: db.comments.filter((comment) => comment.loopId === loop.id).length,
    didLike: Boolean(viewerId && db.likes.some((like) => like.loopId === loop.id && like.userId === viewerId)),
    hashtags: loop.hashtags || extractHashtags(loop.caption),
    mentions: loop.mentions || extractMentions(loop.caption),
    commentsPreview: previewComments(loop.id)
  };
}

function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(Object.assign(new Error("Request body is too large."), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

async function readJSON(req, maxBytes = 1024 * 1024) {
  const body = await readBody(req, maxBytes);
  if (!body.length) {
    return {};
  }
  try {
    return JSON.parse(body.toString("utf8"));
  } catch {
    const error = new Error("Invalid JSON body.");
    error.status = 400;
    throw error;
  }
}

async function readMultipart(req, maxBytes) {
  const type = req.headers["content-type"] || "";
  const boundaryMatch = type.match(/boundary=(?:"([^"]+)"|([^;]+))/i);
  if (!boundaryMatch) {
    const error = new Error("Missing multipart boundary.");
    error.status = 400;
    throw error;
  }
  const boundary = Buffer.from(`--${boundaryMatch[1] || boundaryMatch[2]}`);
  const body = await readBody(req, maxBytes);
  const fields = {};
  const files = {};
  let cursor = body.indexOf(boundary);

  while (cursor !== -1) {
    cursor += boundary.length;
    if (body[cursor] === 45 && body[cursor + 1] === 45) {
      break;
    }
    if (body[cursor] === 13 && body[cursor + 1] === 10) {
      cursor += 2;
    }

    const nextBoundary = body.indexOf(boundary, cursor);
    if (nextBoundary === -1) {
      break;
    }

    let part = body.subarray(cursor, nextBoundary);
    if (part.length >= 2 && part[part.length - 2] === 13 && part[part.length - 1] === 10) {
      part = part.subarray(0, part.length - 2);
    }

    const headerEnd = part.indexOf(Buffer.from("\r\n\r\n"));
    if (headerEnd !== -1) {
      const rawHeaders = part.subarray(0, headerEnd).toString("utf8");
      const content = part.subarray(headerEnd + 4);
      const disposition = rawHeaders.match(/content-disposition:\s*form-data;\s*([^\r\n]+)/i);
      const contentType = rawHeaders.match(/content-type:\s*([^\r\n]+)/i);
      const name = disposition && disposition[1].match(/name="([^"]+)"/i);
      const filename = disposition && disposition[1].match(/filename="([^"]*)"/i);

      if (name) {
        if (filename && filename[1]) {
          files[name[1]] = {
            filename: path.basename(filename[1]),
            contentType: contentType ? contentType[1].trim() : "application/octet-stream",
            data: content
          };
        } else {
          fields[name[1]] = content.toString("utf8");
        }
      }
    }

    cursor = nextBoundary;
  }

  return { fields, files };
}

function findAtom(buffer, wantedType, start = 0, end = buffer.length, depth = 0) {
  let offset = start;
  while (offset + 8 <= end) {
    let size = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    let headerSize = 8;

    if (size === 1 && offset + 16 <= end) {
      size = Number(buffer.readBigUInt64BE(offset + 8));
      headerSize = 16;
    } else if (size === 0) {
      size = end - offset;
    }

    if (size < headerSize || offset + size > end) {
      break;
    }

    const dataStart = offset + headerSize;
    const dataEnd = offset + size;
    if (type === wantedType) {
      return { start: dataStart, end: dataEnd };
    }

    const isContainer = ["moov", "trak", "mdia", "minf", "stbl", "edts", "udta"].includes(type);
    if (isContainer && depth < 8) {
      const found = findAtom(buffer, wantedType, dataStart, dataEnd, depth + 1);
      if (found) {
        return found;
      }
    }

    offset += size;
  }
  return null;
}

function parseQuickTimeDurationSeconds(buffer) {
  const mvhd = findAtom(buffer, "mvhd");
  if (!mvhd || mvhd.end - mvhd.start < 20) {
    return null;
  }

  const version = buffer.readUInt8(mvhd.start);
  if (version === 0 && mvhd.start + 20 <= mvhd.end) {
    const timescale = buffer.readUInt32BE(mvhd.start + 12);
    const duration = buffer.readUInt32BE(mvhd.start + 16);
    return timescale ? duration / timescale : null;
  }

  if (version === 1 && mvhd.start + 32 <= mvhd.end) {
    const timescale = buffer.readUInt32BE(mvhd.start + 20);
    const duration = Number(buffer.readBigUInt64BE(mvhd.start + 24));
    return timescale ? duration / timescale : null;
  }

  return null;
}

function videoContentType(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  if (ext === ".mov") {
    return "video/quicktime";
  }
  if (ext === ".m4v") {
    return "video/x-m4v";
  }
  return "video/mp4";
}

function sendVideo(req, res, fileName) {
  const safeName = path.basename(decodeURIComponent(fileName));
  const filePath = path.join(VIDEO_DIR, safeName);
  if (!filePath.startsWith(VIDEO_DIR) || !fs.existsSync(filePath)) {
    sendError(res, 404, "Video not found.");
    return;
  }

  const stat = fs.statSync(filePath);
  const range = req.headers.range;
  const headers = {
    "Content-Type": videoContentType(safeName),
    "Accept-Ranges": "bytes",
    "Access-Control-Allow-Origin": "*"
  };

  if (!range) {
    res.writeHead(200, { ...headers, "Content-Length": stat.size });
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  const match = range.match(/bytes=(\d*)-(\d*)/);
  if (!match) {
    res.writeHead(416, headers);
    res.end();
    return;
  }

  const start = match[1] ? Number(match[1]) : 0;
  const end = match[2] ? Number(match[2]) : stat.size - 1;
  if (start >= stat.size || end >= stat.size || start > end) {
    res.writeHead(416, { ...headers, "Content-Range": `bytes */${stat.size}` });
    res.end();
    return;
  }

  res.writeHead(206, {
    ...headers,
    "Content-Length": end - start + 1,
    "Content-Range": `bytes ${start}-${end}/${stat.size}`
  });
  fs.createReadStream(filePath, { start, end }).pipe(res);
}

function avatarColorFor(username) {
  const palette = ["#4ADE80", "#22D3EE", "#F97316", "#A78BFA", "#F472B6", "#FACC15"];
  const hash = crypto.createHash("sha256").update(username).digest()[0];
  return palette[hash % palette.length];
}

function extractHashtags(text) {
  return [...new Set(String(text || "").match(/#[a-z0-9_]+/gi)?.map((tag) => tag.slice(1).toLowerCase()) || [])];
}

function extractMentions(text) {
  return [...new Set(String(text || "").match(/@[a-z0-9_]+/gi)?.map((tag) => tag.slice(1).toLowerCase()) || [])];
}

function imageContentType(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  if (ext === ".png") {
    return "image/png";
  }
  if (ext === ".webp") {
    return "image/webp";
  }
  return "image/jpeg";
}

function sendFile(res, directory, fileName, contentType) {
  const safeName = path.basename(decodeURIComponent(fileName));
  const filePath = path.join(directory, safeName);
  if (!filePath.startsWith(directory) || !fs.existsSync(filePath)) {
    sendError(res, 404, "File not found.");
    return;
  }

  const stat = fs.statSync(filePath);
  res.writeHead(200, {
    "Content-Type": contentType,
    "Content-Length": stat.size,
    "Access-Control-Allow-Origin": "*",
    "Cache-Control": "public, max-age=3600"
  });
  fs.createReadStream(filePath).pipe(res);
}

function createNotification(userId, type, actorId, options = {}) {
  if (!userId || userId === actorId) {
    return;
  }
  db.notifications.push({
    id: makeId("not"),
    userId,
    type,
    actorId,
    loopId: options.loopId || null,
    conversationId: options.conversationId || null,
    messageId: options.messageId || null,
    body: options.body || "",
    readAt: null,
    createdAt: nowISO()
  });
}

function formatNotification(req, notification, viewerId) {
  const actor = db.users.find((user) => user.id === notification.actorId);
  const loop = notification.loopId ? db.loops.find((candidate) => candidate.id === notification.loopId) : null;
  return {
    id: notification.id,
    type: notification.type,
    body: notification.body,
    readAt: notification.readAt,
    createdAt: notification.createdAt,
    actor: publicUser(actor, viewerId, req),
    loop: loop ? formatLoop(req, loop, viewerId) : null,
    conversationId: notification.conversationId
  };
}

function conversationFor(userA, userB) {
  const participantIds = [userA, userB].sort();
  let conversation = db.conversations.find((candidate) => {
    const ids = [...candidate.participantIds].sort();
    return ids.length === 2 && ids[0] === participantIds[0] && ids[1] === participantIds[1];
  });
  if (!conversation) {
    conversation = {
      id: makeId("con"),
      participantIds,
      createdAt: nowISO(),
      updatedAt: nowISO()
    };
    db.conversations.push(conversation);
  }
  return conversation;
}

function formatMessage(req, message, viewerId) {
  const sender = db.users.find((user) => user.id === message.senderId);
  const loop = message.loopId ? db.loops.find((candidate) => candidate.id === message.loopId) : null;
  return {
    id: message.id,
    conversationId: message.conversationId,
    body: message.body,
    createdAt: message.createdAt,
    sender: publicUser(sender, viewerId, req),
    loop: loop ? formatLoop(req, loop, viewerId) : null
  };
}

function formatConversation(req, conversation, viewerId) {
  const participants = conversation.participantIds
    .map((id) => db.users.find((user) => user.id === id))
    .filter(Boolean)
    .map((user) => publicUser(user, viewerId, req));
  const messages = db.messages
    .filter((message) => message.conversationId === conversation.id)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const lastMessage = messages[messages.length - 1] || null;
  return {
    id: conversation.id,
    participants,
    lastMessage: lastMessage ? formatMessage(req, lastMessage, viewerId) : null,
    unreadCount: db.notifications.filter(
      (notification) => notification.userId === viewerId && notification.conversationId === conversation.id && !notification.readAt
    ).length,
    updatedAt: conversation.updatedAt,
    createdAt: conversation.createdAt
  };
}

function trendingHashtags() {
  const counts = new Map();
  for (const loop of db.loops) {
    for (const tag of loop.hashtags || extractHashtags(loop.caption)) {
      counts.set(tag, (counts.get(tag) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 20)
    .map(([tag, count]) => ({ tag, count }));
}

async function route(req, res) {
  if (req.method === "OPTIONS") {
    sendJSON(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = decodeURIComponent(url.pathname);

  if (req.method === "GET" && pathname === "/health") {
    sendJSON(res, 200, {
      ok: true,
      app: "Loop",
      storage: DATA_DIR,
      maxDurationSeconds: MAX_DURATION_SECONDS
    });
    return;
  }

  if (req.method === "GET" && pathname.startsWith("/videos/")) {
    sendVideo(req, res, pathname.replace(/^\/videos\//, ""));
    return;
  }

  if (req.method === "GET" && pathname.startsWith("/avatars/")) {
    const fileName = pathname.replace(/^\/avatars\//, "");
    sendFile(res, AVATAR_DIR, fileName, imageContentType(fileName));
    return;
  }

  if (req.method === "POST" && pathname === "/api/auth/signup") {
    const body = await readJSON(req);
    const email = normalizeEmail(body.email);
    const username = normalizeUsername(body.username);
    const password = String(body.password || "");

    if (!assertEmail(email)) {
      sendError(res, 400, "Enter a valid email.");
      return;
    }
    if (!assertUsername(username)) {
      sendError(res, 400, "Usernames need 3-24 lowercase letters, numbers, or underscores.");
      return;
    }
    if (password.length < 8) {
      sendError(res, 400, "Passwords need at least 8 characters.");
      return;
    }
    if (db.users.some((user) => user.email === email)) {
      sendError(res, 409, "That email is already registered.");
      return;
    }
    if (db.users.some((user) => user.username === username)) {
      sendError(res, 409, "That username is already taken.");
      return;
    }

    const user = {
      id: makeId("usr"),
      email,
      username,
      displayName: body.displayName || username,
      passwordHash: hashPassword(password),
      bio: "Making 6 seconds count.",
      avatarColor: avatarColorFor(username),
      createdAt: nowISO()
    };
    db.users.push(user);
    saveDB();
    sendJSON(res, 201, { token: signToken(user.id), user: publicUser(user, user.id, req) });
    return;
  }

  if (req.method === "POST" && pathname === "/api/auth/login") {
    const body = await readJSON(req);
    const login = normalizeEmail(body.email || body.username);
    const password = String(body.password || "");
    const user = db.users.find((candidate) => candidate.email === login || candidate.username === login);
    if (!user || !verifyPassword(password, user.passwordHash)) {
      sendError(res, 401, "Invalid email, username, or password.");
      return;
    }
    sendJSON(res, 200, { token: signToken(user.id), user: publicUser(user, user.id, req) });
    return;
  }

  if (req.method === "GET" && pathname === "/api/me") {
    const viewer = getBearerUser(req);
    sendJSON(res, 200, { user: publicUser(viewer, viewer.id, req) });
    return;
  }

  if (req.method === "PATCH" && pathname === "/api/me") {
    const viewer = getBearerUser(req);
    const body = await readJSON(req);
    const displayName = String(body.displayName || viewer.displayName).trim().slice(0, 48);
    const bio = String(body.bio || "").trim().slice(0, 160);
    viewer.displayName = displayName || viewer.username;
    viewer.bio = bio;
    saveDB();
    sendJSON(res, 200, { user: publicUser(viewer, viewer.id, req) });
    return;
  }

  if (req.method === "POST" && pathname === "/api/me/avatar") {
    const viewer = getBearerUser(req);
    const { files } = await readMultipart(req, 8 * 1024 * 1024);
    const upload = files.avatar;
    if (!upload) {
      sendError(res, 400, "Attach an image file named 'avatar'.");
      return;
    }
    const ext = path.extname(upload.filename).toLowerCase() || ".jpg";
    if (![".jpg", ".jpeg", ".png", ".webp"].includes(ext)) {
      sendError(res, 400, "Avatar must be a JPG, PNG, or WebP image.");
      return;
    }
    const fileName = `${viewer.id}-${Date.now()}${ext}`;
    
    // Attempt cloud upload, fallback to local file
    const cloudURL = await uploadToCloudinary(upload.data, ext);
    if (cloudURL) {
      viewer.avatarURL = cloudURL;
      viewer.avatarFileName = null;
    } else {
      fs.writeFileSync(path.join(AVATAR_DIR, fileName), upload.data);
      viewer.avatarFileName = fileName;
      viewer.avatarURL = null;
    }
    saveDB();
    sendJSON(res, 200, { user: publicUser(viewer, viewer.id, req) });
    return;
  }

  if (req.method === "GET" && pathname === "/api/feed") {
    const viewer = getBearerUser(req);
    const scope = url.searchParams.get("scope") || "forYou";
    const categoryQuery = url.searchParams.get("category") || "both";
    const followingIds = new Set(
      db.follows.filter((follow) => follow.followerId === viewer.id).map((follow) => follow.followingId)
    );
    let loops = [...db.loops];
    if (scope === "following") {
      loops = loops.filter((loop) => loop.creatorId === viewer.id || followingIds.has(loop.creatorId));
    }
    
    if (categoryQuery === "6s") {
      loops = loops.filter((loop) => loop.category === "6s" || (!loop.category && loop.durationSeconds <= 6.25));
    } else if (categoryQuery === "60s") {
      loops = loops.filter((loop) => loop.category === "60s" || (!loop.category && loop.durationSeconds > 6.25));
    }
    
    loops.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    sendJSON(res, 200, { loops: loops.map((loop) => formatLoop(req, loop, viewer.id)) });
    return;
  }

  if (req.method === "GET" && pathname === "/api/discover") {
    const viewer = getBearerUser(req);
    const followingIds = new Set(
      db.follows.filter((follow) => follow.followerId === viewer.id).map((follow) => follow.followingId)
    );
    const users = db.users
      .filter((user) => user.id !== viewer.id && !followingIds.has(user.id))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .slice(0, 12)
      .map((user) => publicUser(user, viewer.id, req));
    const loops = [...db.loops]
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .slice(0, 12)
      .map((loop) => formatLoop(req, loop, viewer.id));
    sendJSON(res, 200, { hashtags: trendingHashtags(), users, loops });
    return;
  }

  if (req.method === "GET" && pathname === "/api/search") {
    const viewer = getBearerUser(req);
    const query = String(url.searchParams.get("q") || "").trim().replace(/^#/, "").toLowerCase();
    const users = query
      ? db.users.filter((user) => user.username.includes(query) || user.displayName.toLowerCase().includes(query))
      : db.users;
    const loops = query
      ? db.loops.filter((loop) => {
          const caption = loop.caption.toLowerCase();
          const hashtags = loop.hashtags || extractHashtags(loop.caption);
          const mentions = loop.mentions || extractMentions(loop.caption);
          return caption.includes(query) || hashtags.includes(query) || mentions.includes(query);
        })
      : [...db.loops];
    const hashtags = query
      ? trendingHashtags().filter((item) => item.tag.includes(query))
      : trendingHashtags();
    sendJSON(res, 200, {
      users: users.slice(0, 30).map((user) => publicUser(user, viewer.id, req)),
      hashtags,
      loops: loops.slice(0, 30).map((loop) => formatLoop(req, loop, viewer.id))
    });
    return;
  }

  if (req.method === "POST" && pathname === "/api/loops") {
    const viewer = getBearerUser(req);
    const { fields, files } = await readMultipart(req, MAX_VIDEO_BYTES + 1024 * 1024);
    const upload = files.video;
    if (!upload) {
      sendError(res, 400, "Attach a video file named 'video'.");
      return;
    }

    const ext = path.extname(upload.filename).toLowerCase() || ".mp4";
    if (![".mp4", ".mov", ".m4v"].includes(ext)) {
      sendError(res, 400, "Loop accepts .mp4, .mov, or .m4v videos.");
      return;
    }

    const detectedDuration = parseQuickTimeDurationSeconds(upload.data);
    const clientDuration = Number(fields.durationSeconds || 0);
    const durationSeconds = detectedDuration || clientDuration;
    if (!durationSeconds) {
      sendError(res, 400, "Could not verify video duration.");
      return;
    }
    if (durationSeconds > MAX_DURATION_SECONDS + DURATION_TOLERANCE_SECONDS) {
      sendError(res, 400, `Loop videos must be ${MAX_DURATION_SECONDS} seconds or less.`, {
        durationSeconds: Number(durationSeconds.toFixed(2)),
        maxDurationSeconds: MAX_DURATION_SECONDS
      });
      return;
    }

    const videoFileName = `${makeId("loop")}${ext}`;
    const caption = String(fields.caption || "").trim().slice(0, 220);
    const category = fields.category === "60s" ? "60s" : "6s";
    
    // Attempt cloud video upload, fallback to local file
    const cloudURL = await uploadToCloudinary(upload.data, ext);
    
    const loop = {
      id: makeId("lop"),
      creatorId: viewer.id,
      caption,
      durationSeconds: Math.min(MAX_DURATION_SECONDS, Number(durationSeconds.toFixed(2))),
      category,
      hashtags: extractHashtags(caption),
      mentions: extractMentions(caption),
      videoFileName: cloudURL ? null : videoFileName,
      videoURL: cloudURL || null,
      createdAt: nowISO()
    };

    if (!cloudURL) {
      fs.writeFileSync(path.join(VIDEO_DIR, videoFileName), upload.data);
    }
    db.loops.push(loop);
    for (const username of loop.mentions) {
      const mentioned = db.users.find((user) => user.username === username);
      if (mentioned) {
        createNotification(mentioned.id, "mention", viewer.id, { loopId: loop.id, body: "mentioned you in a loop" });
      }
    }
    saveDB();
    sendJSON(res, 201, { loop: formatLoop(req, loop, viewer.id) });
    return;
  }

  const loopLikeMatch = pathname.match(/^\/api\/loops\/([^/]+)\/like$/);
  if (loopLikeMatch && (req.method === "POST" || req.method === "DELETE")) {
    const viewer = getBearerUser(req);
    const loopId = loopLikeMatch[1];
    const loop = db.loops.find((candidate) => candidate.id === loopId);
    if (!loop) {
      sendError(res, 404, "Loop not found.");
      return;
    }
    db.likes = db.likes.filter((like) => !(like.loopId === loopId && like.userId === viewer.id));
    if (req.method === "POST") {
      db.likes.push({ loopId, userId: viewer.id, createdAt: nowISO() });
      createNotification(loop.creatorId, "like", viewer.id, { loopId, body: "liked your loop" });
    }
    saveDB();
    sendJSON(res, 200, { loop: formatLoop(req, loop, viewer.id) });
    return;
  }

  const commentsMatch = pathname.match(/^\/api\/loops\/([^/]+)\/comments$/);
  if (commentsMatch && req.method === "GET") {
    const viewer = getBearerUser(req);
    const loopId = commentsMatch[1];
    const comments = db.comments
      .filter((comment) => comment.loopId === loopId)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .map((comment) => ({
        id: comment.id,
        body: comment.body,
        createdAt: comment.createdAt,
        author: publicUser(db.users.find((user) => user.id === comment.userId), viewer.id, req)
      }));
    sendJSON(res, 200, { comments });
    return;
  }

  if (commentsMatch && req.method === "POST") {
    const viewer = getBearerUser(req);
    const loopId = commentsMatch[1];
    const loop = db.loops.find((candidate) => candidate.id === loopId);
    if (!loop) {
      sendError(res, 404, "Loop not found.");
      return;
    }
    const body = await readJSON(req);
    const text = String(body.body || "").trim().slice(0, 280);
    if (!text) {
      sendError(res, 400, "Comment cannot be empty.");
      return;
    }
    const comment = {
      id: makeId("cmt"),
      loopId,
      userId: viewer.id,
      body: text,
      createdAt: nowISO()
    };
    db.comments.push(comment);
    createNotification(loop.creatorId, "comment", viewer.id, { loopId, body: text });
    for (const username of extractMentions(text)) {
      const mentioned = db.users.find((user) => user.username === username);
      if (mentioned) {
        createNotification(mentioned.id, "mention", viewer.id, { loopId, body: text });
      }
    }
    saveDB();
    sendJSON(res, 201, {
      comment: {
        id: comment.id,
        body: comment.body,
        createdAt: comment.createdAt,
        author: publicUser(viewer, viewer.id, req)
      },
      loop: formatLoop(req, loop, viewer.id)
    });
    return;
  }

  const followMatch = pathname.match(/^\/api\/users\/([^/]+)\/follow$/);
  if (followMatch && (req.method === "POST" || req.method === "DELETE")) {
    const viewer = getBearerUser(req);
    const targetId = followMatch[1];
    const target = db.users.find((candidate) => candidate.id === targetId);
    if (!target) {
      sendError(res, 404, "User not found.");
      return;
    }
    if (target.id === viewer.id) {
      sendError(res, 400, "You cannot follow yourself.");
      return;
    }
    db.follows = db.follows.filter(
      (follow) => !(follow.followerId === viewer.id && follow.followingId === target.id)
    );
    if (req.method === "POST") {
      db.follows.push({ followerId: viewer.id, followingId: target.id, createdAt: nowISO() });
      createNotification(target.id, "follow", viewer.id, { body: "started following you" });
    }
    saveDB();
    sendJSON(res, 200, { user: publicUser(target, viewer.id, req) });
    return;
  }

  if (req.method === "GET" && pathname === "/api/notifications") {
    const viewer = getBearerUser(req);
    const notifications = db.notifications
      .filter((notification) => notification.userId === viewer.id)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .slice(0, 60)
      .map((notification) => formatNotification(req, notification, viewer.id));
    sendJSON(res, 200, { notifications });
    return;
  }

  if (req.method === "POST" && pathname === "/api/notifications/read") {
    const viewer = getBearerUser(req);
    const readAt = nowISO();
    for (const notification of db.notifications) {
      if (notification.userId === viewer.id) {
        notification.readAt = notification.readAt || readAt;
      }
    }
    saveDB();
    sendJSON(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET" && pathname === "/api/conversations") {
    const viewer = getBearerUser(req);
    const conversations = db.conversations
      .filter((conversation) => conversation.participantIds.includes(viewer.id))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .map((conversation) => formatConversation(req, conversation, viewer.id));
    sendJSON(res, 200, { conversations });
    return;
  }

  if (req.method === "POST" && pathname === "/api/conversations") {
    const viewer = getBearerUser(req);
    const body = await readJSON(req);
    const target = db.users.find((user) => user.id === body.userId || user.username === normalizeUsername(body.username));
    if (!target) {
      sendError(res, 404, "User not found.");
      return;
    }
    if (target.id === viewer.id) {
      sendError(res, 400, "Choose another user.");
      return;
    }
    const conversation = conversationFor(viewer.id, target.id);
    saveDB();
    sendJSON(res, 200, { conversation: formatConversation(req, conversation, viewer.id) });
    return;
  }

  const messagesMatch = pathname.match(/^\/api\/conversations\/([^/]+)\/messages$/);
  if (messagesMatch && req.method === "GET") {
    const viewer = getBearerUser(req);
    const conversation = db.conversations.find((candidate) => candidate.id === messagesMatch[1]);
    if (!conversation || !conversation.participantIds.includes(viewer.id)) {
      sendError(res, 404, "Conversation not found.");
      return;
    }
    const messages = db.messages
      .filter((message) => message.conversationId === conversation.id)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .map((message) => formatMessage(req, message, viewer.id));
    sendJSON(res, 200, { messages });
    return;
  }

  if (messagesMatch && req.method === "POST") {
    const viewer = getBearerUser(req);
    const conversation = db.conversations.find((candidate) => candidate.id === messagesMatch[1]);
    if (!conversation || !conversation.participantIds.includes(viewer.id)) {
      sendError(res, 404, "Conversation not found.");
      return;
    }
    const body = await readJSON(req);
    const text = String(body.body || "").trim().slice(0, 500);
    const loopId = body.loopId ? String(body.loopId) : null;
    if (!text && !loopId) {
      sendError(res, 400, "Send text or a loop.");
      return;
    }
    if (loopId && !db.loops.some((loop) => loop.id === loopId)) {
      sendError(res, 404, "Loop not found.");
      return;
    }
    const message = {
      id: makeId("msg"),
      conversationId: conversation.id,
      senderId: viewer.id,
      body: text,
      loopId,
      createdAt: nowISO()
    };
    db.messages.push(message);
    conversation.updatedAt = message.createdAt;
    for (const participantId of conversation.participantIds) {
      if (participantId !== viewer.id) {
        createNotification(participantId, "message", viewer.id, {
          conversationId: conversation.id,
          messageId: message.id,
          loopId,
          body: text || "sent you a loop"
        });
      }
    }
    saveDB();
    sendJSON(res, 201, {
      message: formatMessage(req, message, viewer.id),
      conversation: formatConversation(req, conversation, viewer.id)
    });
    return;
  }

  const userLoopsMatch = pathname.match(/^\/api\/users\/([^/]+)\/loops$/);
  if (userLoopsMatch && req.method === "GET") {
    const viewer = getBearerUser(req);
    const userId = userLoopsMatch[1];
    const user = db.users.find((candidate) => candidate.id === userId);
    if (!user) {
      sendError(res, 404, "User not found.");
      return;
    }
    const loops = db.loops
      .filter((loop) => loop.creatorId === userId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .map((loop) => formatLoop(req, loop, viewer.id));
    sendJSON(res, 200, { user: publicUser(user, viewer.id, req), loops });
    return;
  }

  const userMatch = pathname.match(/^\/api\/users\/([^/]+)$/);
  if (userMatch && req.method === "GET") {
    const viewer = getBearerUser(req);
    const idOrUsername = userMatch[1].replace(/^@/, "").toLowerCase();
    const user = db.users.find((candidate) => candidate.id === idOrUsername || candidate.username === idOrUsername);
    if (!user) {
      sendError(res, 404, "User not found.");
      return;
    }
    sendJSON(res, 200, { user: publicUser(user, viewer.id, req) });
    return;
  }

  sendError(res, 404, "Route not found.");
}

function publishServerURL() {
  const cloudName = CLOUDINARY_CLOUD_NAME;
  const apiKey = CLOUDINARY_API_KEY;
  const apiSecret = CLOUDINARY_API_SECRET;
  
  if (!cloudName || !apiKey || !apiSecret) {
    console.log("[loop] Cloudinary credentials not configured; skipping URL publication.");
    return;
  }
  
  const targetURL = process.env.SERVER_URL || process.env.RENDER_EXTERNAL_URL || process.env.KOYEB_PUBLIC_URL;
  
  if (!targetURL) {
    console.log("[loop] No SERVER_URL/RENDER_EXTERNAL_URL found; skipping URL publication. Deploy to Render/Koyeb to publish static URL.");
    return;
  }
  
  console.log(`[loop] publishing server URL (${targetURL}) to Cloudinary...`);
  
  const base64Data = Buffer.from(targetURL).toString("base64");
  const dataUrl = `data:text/plain;base64,${base64Data}`;
  
  const postData = JSON.stringify({
    file: dataUrl,
    public_id: "loop_server_url.txt",
    invalidate: true
  });
  
  const options = {
    hostname: "api.cloudinary.com",
    port: 443,
    path: `/v1_1/${cloudName}/raw/upload`,
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(postData),
      "Authorization": CLOUDINARY_AUTH
    }
  };
  
  const req = https.request(options, (res) => {
    let body = "";
    res.on("data", (chunk) => body += chunk);
    res.on("end", () => {
      try {
        const json = JSON.parse(body);
        if (json.secure_url) {
          console.log(`[loop] server URL successfully published to Cloudinary!`);
        } else {
          console.error("[loop] failed to publish server URL to Cloudinary:", json.error?.message || json);
        }
      } catch (e) {
        console.error("[loop] parse error publishing server URL:", e);
      }
    });
  });
  
  req.on("error", (e) => {
    console.error("[loop] network error publishing server URL:", e);
  });
  
  req.write(postData);
  req.end();
}

const server = http.createServer((req, res) => {
  route(req, res).catch((error) => {
    const status = error.status || 500;
    if (status >= 500) {
      console.error("[loop] request failed", error);
    }
    sendError(res, status, error.message || "Server error.");
  });
});

async function startServer() {
  db = await loadDB();
  saveDB(); // Upload the initial encrypted database backup on startup
  server.listen(PORT, HOST, () => {
    console.log(`[loop] server listening on http://${HOST}:${PORT}`);
    console.log(`[loop] storing videos and db in ${DATA_DIR}`);
    publishServerURL();
  });
}

// Handle cleanup on exit
process.on("SIGINT", () => {
  process.exit(0);
});

process.on("SIGTERM", () => {
  process.exit(0);
});

startServer();
