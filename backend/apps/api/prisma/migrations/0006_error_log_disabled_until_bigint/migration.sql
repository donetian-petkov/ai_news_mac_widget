-- Rebuild existing local ErrorLogRecord tables that were created before
-- disabledUntilMs was corrected from INT to BIGINT.
PRAGMA foreign_keys=OFF;

CREATE TABLE "new_ErrorLogRecord" (
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

INSERT INTO "new_ErrorLogRecord" (
    "id",
    "category",
    "feedUrl",
    "feedLabel",
    "attempt",
    "maxAttempts",
    "failCount",
    "disabledUntilMs",
    "message",
    "detailsJson",
    "createdAt"
)
SELECT
    "id",
    "category",
    "feedUrl",
    "feedLabel",
    "attempt",
    "maxAttempts",
    "failCount",
    "disabledUntilMs",
    "message",
    "detailsJson",
    "createdAt"
FROM "ErrorLogRecord";

DROP TABLE "ErrorLogRecord";
ALTER TABLE "new_ErrorLogRecord" RENAME TO "ErrorLogRecord";

CREATE INDEX "ErrorLogRecord_category_createdAt_idx" ON "ErrorLogRecord"("category", "createdAt");
CREATE INDEX "ErrorLogRecord_feedUrl_createdAt_idx" ON "ErrorLogRecord"("feedUrl", "createdAt");

PRAGMA foreign_keys=ON;
