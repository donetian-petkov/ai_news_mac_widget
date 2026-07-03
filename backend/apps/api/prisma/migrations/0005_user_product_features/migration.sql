CREATE TABLE IF NOT EXISTS "UserFeatureRecord" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "userId" INTEGER NOT NULL,
  "kind" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "payloadJson" TEXT NOT NULL,
  "archived" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" DATETIME NOT NULL,
  CONSTRAINT "UserFeatureRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "UserFeatureRecord_userId_kind_updatedAt_idx" ON "UserFeatureRecord"("userId", "kind", "updatedAt");
CREATE INDEX IF NOT EXISTS "UserFeatureRecord_kind_updatedAt_idx" ON "UserFeatureRecord"("kind", "updatedAt");

CREATE TABLE IF NOT EXISTS "DeliveryHistoryRecord" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "userId" INTEGER,
  "feedUrl" TEXT,
  "itemId" TEXT,
  "title" TEXT,
  "source" TEXT,
  "stage" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "reason" TEXT,
  "detailsJson" TEXT,
  "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_userId_createdAt_idx" ON "DeliveryHistoryRecord"("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_feedUrl_createdAt_idx" ON "DeliveryHistoryRecord"("feedUrl", "createdAt");
CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_stage_status_createdAt_idx" ON "DeliveryHistoryRecord"("stage", "status", "createdAt");

CREATE TABLE IF NOT EXISTS "ShareLink" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "token" TEXT NOT NULL,
  "userId" INTEGER NOT NULL,
  "kind" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "payloadJson" TEXT NOT NULL,
  "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" DATETIME,
  CONSTRAINT "ShareLink_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "ShareLink_token_key" ON "ShareLink"("token");
CREATE INDEX IF NOT EXISTS "ShareLink_userId_createdAt_idx" ON "ShareLink"("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "ShareLink_kind_createdAt_idx" ON "ShareLink"("kind", "createdAt");
