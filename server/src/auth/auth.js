import crypto from "node:crypto";
import argon2 from "argon2";

const ACCESS_TOKEN_TTL = "15m";
const REFRESH_TOKEN_DAYS = 30;

function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

function createRefreshToken() {
  return crypto.randomBytes(48).toString("base64url");
}

export async function registerUser(db, email, password) {
  const normalizedEmail = email.trim().toLowerCase();

  if (!normalizedEmail || !normalizedEmail.includes("@")) {
    const error = new Error("Invalid email address");
    error.statusCode = 400;
    throw error;
  }

  if (typeof password !== "string" || password.length < 8) {
    const error = new Error("Password must contain at least 8 characters");
    error.statusCode = 400;
    throw error;
  }

  const existing = await db.query(
    "SELECT id FROM users WHERE email = $1",
    [normalizedEmail]
  );

  if (existing.rowCount > 0) {
    const error = new Error("Account already exists");
    error.statusCode = 409;
    throw error;
  }

  const passwordHash = await argon2.hash(password, {
    type: argon2.argon2id
  });

  const result = await db.query(
    `INSERT INTO users (email, password_hash)
     VALUES ($1, $2)
     RETURNING id, email, created_at`,
    [normalizedEmail, passwordHash]
  );

  return result.rows[0];
}

export async function authenticateUser(db, email, password) {
  const normalizedEmail = email.trim().toLowerCase();

  const result = await db.query(
    `SELECT id, email, password_hash
     FROM users
     WHERE email = $1`,
    [normalizedEmail]
  );

  if (result.rowCount === 0) {
    const error = new Error("Invalid email or password");
    error.statusCode = 401;
    throw error;
  }

  const user = result.rows[0];

  const valid = await argon2.verify(
    user.password_hash,
    password
  );

  if (!valid) {
    const error = new Error("Invalid email or password");
    error.statusCode = 401;
    throw error;
  }

  return {
    id: user.id,
    email: user.email
  };
}

export async function createSession(db, jwt, user) {
  const accessToken = await jwt.sign(
    {
      sub: user.id,
      email: user.email
    },
    {
      expiresIn: ACCESS_TOKEN_TTL
    }
  );

  const refreshToken = createRefreshToken();
  const refreshTokenHash = hashToken(refreshToken);

  const expiresAt = new Date(
    Date.now() + REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000
  );

  await db.query(
    `INSERT INTO refresh_tokens
      (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [user.id, refreshTokenHash, expiresAt]
  );

  return {
    accessToken,
    refreshToken,
    expiresIn: 900
  };
}

export async function refreshSession(db, jwt, refreshToken) {
  const tokenHash = hashToken(refreshToken);

  const result = await db.query(
    `SELECT
       refresh_tokens.id,
       refresh_tokens.user_id,
       users.email
     FROM refresh_tokens
     JOIN users ON users.id = refresh_tokens.user_id
     WHERE refresh_tokens.token_hash = $1
       AND refresh_tokens.revoked_at IS NULL
       AND refresh_tokens.expires_at > NOW()`,
    [tokenHash]
  );

  if (result.rowCount === 0) {
    const error = new Error("Invalid refresh token");
    error.statusCode = 401;
    throw error;
  }

  const session = result.rows[0];

  await db.query(
    `UPDATE refresh_tokens
     SET revoked_at = NOW()
     WHERE id = $1`,
    [session.id]
  );

  return createSession(db, jwt, {
    id: session.user_id,
    email: session.email
  });
}

export async function revokeSession(db, refreshToken) {
  const tokenHash = hashToken(refreshToken);

  await db.query(
    `UPDATE refresh_tokens
     SET revoked_at = NOW()
     WHERE token_hash = $1`,
    [tokenHash]
  );
}
