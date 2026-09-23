export async function listDevices(db, userId) {
  const result = await db.query(
    `SELECT
       id,
       name,
       type,
       platform,
       version,
       hostname,
       last_seen_at,
       created_at
     FROM devices
     WHERE user_id = $1
     ORDER BY created_at DESC`,
    [userId]
  );

  return result.rows;
}

export async function createDevice(db, userId, data) {
  const result = await db.query(
    `INSERT INTO devices
      (user_id, name, type, platform, version, hostname)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING
       id,
       name,
       type,
       platform,
       version,
       hostname,
       last_seen_at,
       created_at`,
    [
      userId,
      data.name,
      data.type,
      data.platform ?? null,
      data.version ?? null,
      data.hostname ?? null
    ]
  );

  return result.rows[0];
}

export async function deleteDevice(db, userId, deviceId) {
  const result = await db.query(
    `DELETE FROM devices
     WHERE id = $1 AND user_id = $2
     RETURNING id`,
    [deviceId, userId]
  );

  return result.rowCount > 0;
}

export async function heartbeatDevice(db, userId, deviceId) {
  const result = await db.query(
    `UPDATE devices
     SET last_seen_at = NOW(),
         updated_at = NOW()
     WHERE id = $1 AND user_id = $2
     RETURNING
       id,
       name,
       type,
       platform,
       version,
       hostname,
       last_seen_at,
       created_at,
       updated_at`,
    [deviceId, userId]
  );

  return result.rows[0] ?? null;
}
