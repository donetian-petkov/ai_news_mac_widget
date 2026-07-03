-- CreateTable
CREATE TABLE "ErrorLogRecord" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "category" TEXT NOT NULL,
    "feedUrl" TEXT,
    "feedLabel" TEXT,
    "attempt" INTEGER,
    "maxAttempts" INTEGER,
    "failCount" INTEGER,
    "disabledUntilMs" BIGINT,
    "message" TEXT NOT NULL,
    "detailsJson" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateIndex
CREATE INDEX "ErrorLogRecord_category_createdAt_idx" ON "ErrorLogRecord"("category", "createdAt");

-- CreateIndex
CREATE INDEX "ErrorLogRecord_feedUrl_createdAt_idx" ON "ErrorLogRecord"("feedUrl", "createdAt");
