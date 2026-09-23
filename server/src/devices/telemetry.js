export async function createTelemetry(db, userId, deviceId, data) {
  const deviceResult = await db.query(
    `SELECT id
     FROM devices
     WHERE id = $1 AND user_id = $2`,
    [deviceId, userId]
  );

  if (deviceResult.rowCount === 0) {
    return null;
  }

  const result = await db.query(
    `INSERT INTO device_telemetry (
       device_id,
       model,
       platform,
       os_version,
       app_version,
       storage_total,
       storage_used,
       storage_free,
       memory_total,
       memory_available,
       battery_level,
       battery_state,
       network_type
     )
     VALUES (
       $1, $2, $3, $4, $5, $6, $7,
       $8, $9, $10, $11, $12, $13
     )
     RETURNING
       id,
       device_id,
       model,
       platform,
       os_version,
       app_version,
       storage_total,
       storage_used,
       storage_free,
       memory_total,
       memory_available,
       battery_level,
       battery_state,
       network_type,
       collected_at,
       created_at`,
    [
      deviceId,
      data.model ?? null,
      data.platform ?? null,
      data.osVersion ?? null,
      data.appVersion ?? null,
      data.storageTotal ?? null,
      data.storageUsed ?? null,
      data.storageFree ?? null,
      data.memoryTotal ?? null,
      data.memoryAvailable ?? null,
      data.batteryLevel ?? null,
      data.batteryState ?? null,
      data.networkType ?? null
    ]
  );

  return result.rows[0];
}

export async function getLatestTelemetry(db, userId, deviceId) {
  const result = await db.query(
    `SELECT
       t.id,
       t.device_id,
       t.model,
       t.platform,
       t.os_version,
       t.app_version,
       t.storage_total,
       t.storage_used,
       t.storage_free,
       t.memory_total,
       t.memory_available,
       t.battery_level,
       t.battery_state,
       t.network_type,
       t.collected_at,
       t.created_at
     FROM device_telemetry t
     INNER JOIN devices d
       ON d.id = t.device_id
     WHERE t.device_id = $1
       AND d.user_id = $2
     ORDER BY t.collected_at DESC
     LIMIT 1`,
    [deviceId, userId]
  );

  return result.rows[0] ?? null;
}

export async function listTelemetry(db, userId, deviceId, hours = 24) {
  const result = await db.query(
    `SELECT
       t.id,
       t.device_id,
       t.model,
       t.platform,
       t.os_version,
       t.app_version,
       t.storage_total,
       t.storage_used,
       t.storage_free,
       t.memory_total,
       t.memory_available,
       t.battery_level,
       t.battery_state,
       t.network_type,
       t.collected_at,
       t.created_at
     FROM device_telemetry t
     INNER JOIN devices d
       ON d.id = t.device_id
     WHERE t.device_id = $1
       AND d.user_id = $2
       AND t.collected_at >= now() - ($3::int * INTERVAL '1 hour')
     ORDER BY t.collected_at ASC`,
    [deviceId, userId, hours]
  );

  return result.rows;
}
