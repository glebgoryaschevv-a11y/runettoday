CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
email TEXT NOT NULL UNIQUE,
password_hash TEXT NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
token_hash TEXT NOT NULL UNIQUE,
expires_at TIMESTAMPTZ NOT NULL,
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx
ON refresh_tokens(user_id);

CREATE TABLE IF NOT EXISTS devices (
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
name TEXT NOT NULL,
type TEXT NOT NULL,
platform TEXT,
version TEXT,
hostname TEXT,
last_seen_at TIMESTAMPTZ,
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS devices_user_id_idx
ON devices(user_id);

CREATE TABLE IF NOT EXISTS device_telemetry (
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
model TEXT,
platform TEXT,
os_version TEXT,
app_version TEXT,

storage_total BIGINT,
storage_used BIGINT,
storage_free BIGINT,

memory_total BIGINT,
memory_available BIGINT,

battery_level REAL,
battery_state TEXT,

network_type TEXT,

collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS device_telemetry_device_id_idx
ON device_telemetry(device_id);

CREATE INDEX IF NOT EXISTS device_telemetry_collected_at_idx
ON device_telemetry(collected_at DESC);
