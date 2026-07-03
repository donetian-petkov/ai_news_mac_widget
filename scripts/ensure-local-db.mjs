import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const apiDir = path.join(rootDir, "backend", "apps", "api");
const prismaDir = path.join(apiDir, "prisma");
const dbPath = path.join(prismaDir, "dev.db");
const databaseUrl = process.env.DATABASE_URL || `file:${dbPath}`;

fs.mkdirSync(prismaDir, { recursive: true });
if (!fs.existsSync(dbPath)) {
  fs.closeSync(fs.openSync(dbPath, "a"));
}

function runPrisma(args) {
  return spawnSync("npx", ["prisma", ...args], {
    cwd: apiDir,
    stdio: "inherit",
    env: {
      ...process.env,
      DATABASE_URL: databaseUrl
    }
  });
}

console.log(`[db-init] Using ${databaseUrl}`);

const migrate = runPrisma(["migrate", "deploy", "--schema", "prisma/schema.prisma"]);
if (migrate.status === 0) {
  process.exit(0);
}

console.warn("[db-init] prisma migrate deploy failed, falling back to prisma db push for local bootstrap.");
const push = runPrisma(["db", "push", "--accept-data-loss", "--schema", "prisma/schema.prisma"]);
process.exit(push.status ?? 1);
