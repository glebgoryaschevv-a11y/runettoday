import pg from "pg";

const { Pool } = pg;

let pool;

export function initDatabase(connectionString) {
  pool = new Pool({
    connectionString,
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000
  });

  return pool;
}

export function db() {
  if (!pool) {
    throw new Error("Database has not been initialized");
  }

  return pool;
}
