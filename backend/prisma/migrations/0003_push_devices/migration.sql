-- Push notification device tokens + per-user notification preferences.

CREATE TABLE "DeviceToken" (
  "id"         TEXT PRIMARY KEY,
  "userId"     TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "token"      TEXT NOT NULL UNIQUE,
  "platform"   TEXT NOT NULL DEFAULT 'android',
  "lastSeenAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "DeviceToken_userId_idx" ON "DeviceToken"("userId");

ALTER TABLE "User" ADD COLUMN "notificationPrefs" JSONB;
