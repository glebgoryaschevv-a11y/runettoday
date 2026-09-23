import fs from "node:fs";
import path from "node:path";
import Fastify from "fastify";
import cors from "@fastify/cors";
import fastifyJwt from "@fastify/jwt";
import dotenv from "dotenv";

import { fileURLToPath } from "node:url";

import { initDatabase, db } from "./db.js";
import {
  registerUser,
  authenticateUser,
  createSession,
  refreshSession,
  revokeSession
} from "./auth/auth.js";
import {
  listDevices,
  createDevice,
  deleteDevice,
  heartbeatDevice
} from "./devices/devices.js";
import {
  createTelemetry,
  getLatestTelemetry,
  listTelemetry
} from "./devices/telemetry.js";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const configPath = path.resolve(
  __dirname,
  "../config/default.json"
);

const fileConfig = JSON.parse(
  fs.readFileSync(configPath, "utf8")
);

const config = {
  ...fileConfig,
  host: process.env.RUNETTODAY_HOST || fileConfig.host,
  port: Number(
    process.env.RUNETTODAY_PORT || fileConfig.port
  ),
  databaseUrl:
    process.env.RUNETTODAY_DATABASE_URL ||
    fileConfig.databaseUrl,
  jwtSecret:
    process.env.RUNETTODAY_JWT_SECRET ||
    fileConfig.jwtSecret
};

if (
  config.databaseUrl.includes("CHANGE_ME") ||
  config.jwtSecret === "CHANGE_ME"
) {
  console.error(
    "RunetToday is not configured. Set RUNETTODAY_DATABASE_URL and RUNETTODAY_JWT_SECRET."
  );
  process.exit(1);
}

const app = Fastify({
  logger: true
});

await app.register(cors, {
  origin: true
});

await app.register(fastifyJwt, {
  secret: config.jwtSecret
});

initDatabase(config.databaseUrl);

app.decorate(
  "authenticate",
  async function authenticate(request, reply) {
    try {
      await request.jwtVerify();
    } catch {
      return reply.code(401).send({
        error: "Unauthorized"
      });
    }
  }
);

app.get("/health", async () => {
  await db().query("SELECT 1");

  return {
    ok: true,
    service: "runettoday-api"
  };
});

app.post("/api/v1/auth/register", async (request, reply) => {
  try {
    const { email, password } = request.body ?? {};

    const user = await registerUser(
      db(),
      email,
      password
    );

    const session = await createSession(
      db(),
      app.jwt,
      user
    );

    return reply.code(201).send({
      user,
      ...session
    });
  } catch (error) {
    return reply
      .code(error.statusCode || 500)
      .send({
        error: error.message
      });
  }
});

app.post("/api/v1/auth/login", async (request, reply) => {
  try {
    const { email, password } = request.body ?? {};

    const user = await authenticateUser(
      db(),
      email,
      password
    );

    const session = await createSession(
      db(),
      app.jwt,
      user
    );

    return {
      user,
      ...session
    };
  } catch (error) {
    return reply
      .code(error.statusCode || 500)
      .send({
        error: error.message
      });
  }
});

app.post("/api/v1/auth/refresh", async (request, reply) => {
  try {
    const { refreshToken } = request.body ?? {};

    if (!refreshToken) {
      return reply.code(400).send({
        error: "refreshToken is required"
      });
    }

    return await refreshSession(
      db(),
      app.jwt,
      refreshToken
    );
  } catch (error) {
    return reply
      .code(error.statusCode || 500)
      .send({
        error: error.message
      });
  }
});

app.post("/api/v1/auth/logout", async (request, reply) => {
  const { refreshToken } = request.body ?? {};

  if (refreshToken) {
    await revokeSession(
      db(),
      refreshToken
    );
  }

  return {
    ok: true
  };
});

app.get(
  "/api/v1/me",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const result = await db().query(
      `SELECT id, email, created_at
       FROM users
       WHERE id = $1`,
      [request.user.sub]
    );

    if (result.rowCount === 0) {
      return {
        error: "User not found"
      };
    }

    return {
      user: result.rows[0]
    };
  }
);

app.get(
  "/api/v1/devices",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    return {
      devices: await listDevices(
        db(),
        request.user.sub
      )
    };
  }
);

app.post(
  "/api/v1/devices",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const { name, type, platform, version, hostname } =
      request.body ?? {};

    if (!name || !type) {
      return {
        error: "name and type are required"
      };
    }

    const device = await createDevice(
      db(),
      request.user.sub,
      {
        name,
        type,
        platform,
        version,
        hostname
      }
    );

    return {
      device
    };
  }
);


app.post(
  "/api/v1/devices/:id/heartbeat",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const device = await heartbeatDevice(
      db(),
      request.user.sub,
      request.params.id
    );

    if (!device) {
      return {
        error: "Device not found"
      };
    }

    return {
      device
    };
  }
);

app.post(
  "/api/v1/devices/:id/telemetry",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const telemetry = await createTelemetry(
      db(),
      request.user.sub,
      request.params.id,
      request.body ?? {}
    );

    if (!telemetry) {
      return {
        error: "Device not found"
      };
    }

    return {
      telemetry
    };
  }
);

app.get(
  "/api/v1/devices/:id/telemetry",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const hours = Math.min(
      Math.max(Number(request.query?.hours) || 24, 1),
      168
    );

    return {
      telemetry: await listTelemetry(
        db(),
        request.user.sub,
        request.params.id,
        hours
      )
    };
  }
);

app.get(
  "/api/v1/devices/:id/telemetry/latest",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const telemetry = await getLatestTelemetry(
      db(),
      request.user.sub,
      request.params.id
    );

    if (!telemetry) {
      return {
        error: "Telemetry not found"
      };
    }

    return {
      telemetry
    };
  }
);

app.delete(
  "/api/v1/devices/:id",
  {
    preHandler: [app.authenticate]
  },
  async request => {
    const deleted = await deleteDevice(
      db(),
      request.user.sub,
      request.params.id
    );

    if (!deleted) {
      return {
        error: "Device not found"
      };
    }

    return {
      ok: true
    };
  }
);

try {
  await app.listen({
    host: config.host,
    port: config.port
  });
} catch (error) {
  app.log.error(error);
  process.exit(1);
}
