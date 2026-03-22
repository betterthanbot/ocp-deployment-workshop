#!/bin/bash
set -euo pipefail

# ── Validate required environment variables ──────────────────────────────────
: "${MONGODB_HOST:?MONGODB_HOST is required}"
: "${MONGODB_ADMIN_PASSWORD:?MONGODB_ADMIN_PASSWORD is required}"
: "${MONGODB_DATABASE:?MONGODB_DATABASE is required}"
: "${MONGODB_USER:?MONGODB_USER is required}"
: "${MONGODB_PASSWORD:?MONGODB_PASSWORD is required}"
: "${BACKEND_URL:?BACKEND_URL is required}"

# ── 1. Wait for MongoDB to be reachable ───────────────────────────────────────
echo "[init] Waiting for MongoDB at ${MONGODB_HOST}..."
until mongosh \
  --host "${MONGODB_HOST}" \
  --username admin \
  --password "${MONGODB_ADMIN_PASSWORD}" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet 2>/dev/null; do
  echo "[init] MongoDB not ready, retrying in 5s..."
  sleep 5
done
echo "[init] MongoDB is up."

# ── 2. Create app user and database ──────────────────────────────────────────
echo "[init] Creating app user in database '${MONGODB_DATABASE}'..."
mongosh \
  --host "${MONGODB_HOST}" \
  --username admin \
  --password "${MONGODB_ADMIN_PASSWORD}" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    db = db.getSiblingDB('${MONGODB_DATABASE}');
    if (db.getUser('${MONGODB_USER}') == null) {
      db.createUser({
        user: '${MONGODB_USER}',
        pwd:  '${MONGODB_PASSWORD}',
        roles: [
          { role: 'dbAdmin',   db: '${MONGODB_DATABASE}' },
          { role: 'readWrite', db: '${MONGODB_DATABASE}' }
        ]
      });
      print('[init] User created.');
    } else {
      print('[init] User already exists, skipping.');
    }
  "

# ── 3. Trigger data load via internal service ─────────────────────────────────
echo "[init] Loading initial park data via ${BACKEND_URL}/ws/data/load ..."
if curl -sf "${BACKEND_URL}/ws/data/load"; then
  echo "[init] Data loaded successfully."
else
  echo "[init] WARNING: Data load failed — backend may not be ready yet."
  # Exit non-zero so OpenShift can retry the init container if needed
  exit 1
fi

echo "[init] Initialisation complete."