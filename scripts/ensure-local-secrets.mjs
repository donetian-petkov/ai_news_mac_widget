import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const envPath = path.join(rootDir, ".env");

function randomSecret(bytes = 32) {
  return crypto.randomBytes(bytes).toString("base64url");
}

let content = "";
if (fs.existsSync(envPath)) {
  content = fs.readFileSync(envPath, "utf8");
}

const lines = content ? content.split(/\r?\n/) : [];
const envMap = new Map();
for (const line of lines) {
  const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (match) {
    envMap.set(match[1], match[2]);
  }
}

let changed = false;
if (!envMap.get("AUTH_TOKEN_SECRET")) {
  envMap.set("AUTH_TOKEN_SECRET", randomSecret(48));
  changed = true;
}
if (!envMap.get("KEY_ENCRYPTION_SECRET")) {
  envMap.set("KEY_ENCRYPTION_SECRET", randomSecret(48));
  changed = true;
}

if (changed) {
  const preserved = lines.filter(line => !/^\s*(AUTH_TOKEN_SECRET|KEY_ENCRYPTION_SECRET)\s*=/.test(line));
  preserved.push(`AUTH_TOKEN_SECRET=${envMap.get("AUTH_TOKEN_SECRET")}`);
  preserved.push(`KEY_ENCRYPTION_SECRET=${envMap.get("KEY_ENCRYPTION_SECRET")}`);
  const next = `${preserved.filter((line, index, arr) => !(line === "" && arr[index - 1] === "")).join("\n").replace(/\n*$/, "\n")}`;
  fs.writeFileSync(envPath, next, "utf8");
  console.log(`[secrets-init] Wrote local secrets to ${envPath}`);
} else {
  console.log(`[secrets-init] Local secrets already configured in ${envPath}`);
}
