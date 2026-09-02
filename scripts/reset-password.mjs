import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { PrismaClient } from '@prisma/client';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const apiDir = path.join(root, 'backend', 'apps', 'api');
const defaultDbPath = path.join(apiDir, 'prisma', 'dev.db');

dotenv.config({ path: path.join(root, '.env'), quiet: true });
dotenv.config({ path: path.join(apiDir, '.env'), override: false, quiet: true });
process.env.DATABASE_URL ||= `file:${defaultDbPath}`;

const args = process.argv.slice(2);
const username = String(args[0] || '').trim().toLowerCase();
const requestedPassword = args.includes('--temporary') ? '' : String(args[1] || '');
const temporary = args.includes('--temporary');

if (!username) {
  console.error('Usage: npm run password:reset -- <username> [new-password]');
  console.error('       npm run password:reset -- <username> --temporary');
  process.exit(2);
}

if (!temporary && requestedPassword.length < 6) {
  console.error('New password must be at least 6 characters.');
  process.exit(2);
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const derived = crypto.scryptSync(String(password || ''), salt, 64);
  return `s1:${salt.toString('hex')}:${derived.toString('hex')}`;
}

const prisma = new PrismaClient();

try {
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) {
    console.error(`No local account exists for ${username}.`);
    process.exitCode = 1;
  } else {
    const password = temporary
      ? `Temp-${crypto.randomBytes(12).toString('base64url')}!`
      : requestedPassword;
    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash: hashPassword(password) }
    });
    console.log(`Password reset for ${username}.`);
    if (temporary) {
      console.log(`Temporary password: ${password}`);
    }
  }
} finally {
  await prisma.$disconnect();
}
