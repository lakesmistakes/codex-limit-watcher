const assert = require("node:assert/strict");
const path = require("node:path");
const {
  AUTH_EXPIRED_BODY,
  AUTH_EXPIRED_TITLE,
  createAuthExpiredNotificationEvent,
  getAuthExpiredState,
} = require("../src/authExpired");
const {
  buildBillboardArgs,
  normalizeNotificationSettings,
  shouldShowBillboard,
} = require("../src/notifier");

function buildError(message, diagnostics = {}) {
  return {
    message,
    appServerDiagnostics: diagnostics,
  };
}

try {
  const firstFailure = getAuthExpiredState(buildError(
    "401 Unauthorized",
    { recentStderr: ["Your authentication token has been invalidated. Please try signing in again."] },
  ), false);
  assert.equal(firstFailure.authExpired, true);
  assert.equal(firstFailure.shouldNotify, true);
  assert.equal(firstFailure.nextSuppressed, true);
  assert.deepEqual(firstFailure.matchedSignals, [
    "401 Unauthorized",
    "Your authentication token has been invalidated",
    "signing in again",
  ]);

  const repeatedFailure = getAuthExpiredState(buildError(
    "request failed",
    { recentStdout: ["token_invalidated"] },
  ), firstFailure.nextSuppressed);
  assert.equal(repeatedFailure.authExpired, true);
  assert.equal(repeatedFailure.shouldNotify, false);
  assert.equal(repeatedFailure.nextSuppressed, true);

  const recoveredSuppression = false;
  const laterFailure = getAuthExpiredState(buildError(
    "request failed",
    { recentStderr: ["Your authentication token has been invalidated. Please try signing in again."] },
  ), recoveredSuppression);
  assert.equal(laterFailure.authExpired, true);
  assert.equal(laterFailure.shouldNotify, true);
  assert.equal(laterFailure.nextSuppressed, true);

  const nonAuthFailure = getAuthExpiredState(buildError("Timed out waiting for account/rateLimits/read"), false);
  assert.equal(nonAuthFailure.authExpired, false);
  assert.equal(nonAuthFailure.shouldNotify, false);
  assert.equal(nonAuthFailure.nextSuppressed, false);

  const event = createAuthExpiredNotificationEvent(new Date("2026-05-19T12:00:00.000Z"));
  assert.equal(event.type, "authExpired");
  assert.equal(event.bucket, "auth");
  assert.equal(event.newResetsAtIso, "2026-05-19T12:00:00.000Z");
  assert.equal(AUTH_EXPIRED_TITLE, "Codex auth expired");
  assert.equal(AUTH_EXPIRED_BODY, "Open Codex and sign in again. Limit Watcher cannot read usage right now.");

  assert.equal(shouldShowBillboard("authExpired"), true);

  const rootDir = path.resolve(__dirname, "..");
  const settings = normalizeNotificationSettings({
    notifications: {
      toastEnabled: true,
      soundEnabled: true,
      billboardEnabled: true,
      billboardImage: "assets/billboards/usage-reset-lock-in.png",
    },
    billboard: {
      maxWidth: 400,
      maxHeight: 300,
      position: "bottomRight",
    },
    display: {
      timeZone: "local",
      resetTimeFormat: "weekdayTime",
      triggeredTimeFormat: "dateTime",
    },
  }, rootDir);
  const displayInfo = {
    formattedResetTimestamp: "Scheduled Tuesday at 11:59 PM",
    formattedTriggeredTimestamp: "Triggered May 19, 2026 at 11:59 PM",
  };
  const authBillboardArgs = buildBillboardArgs(rootDir, event, {
    title: AUTH_EXPIRED_TITLE,
    body: AUTH_EXPIRED_BODY,
  }, settings, displayInfo);
  assert.equal(authBillboardArgs.includes("-ImagePath"), false);

  const weeklyArgs = buildBillboardArgs(rootDir, {
    type: "weekly",
    bucket: "weekly",
    oldUsedPercent: 99,
    newUsedPercent: 5,
    newResetsAtIso: "2026-05-20T04:59:34.723Z",
  }, {
    title: "Weekly reset",
    body: "Weekly Codex limit is back.",
  }, settings, displayInfo);
  const weeklyImagePathIndex = weeklyArgs.indexOf("-ImagePath");
  assert.notEqual(weeklyImagePathIndex, -1);
  assert.equal(weeklyArgs[weeklyImagePathIndex + 1], settings.billboardImageAsset.resolvedPath);

  const primaryArgs = buildBillboardArgs(rootDir, {
    type: "primary5h",
    bucket: "5-hour",
    oldUsedPercent: 100,
    newUsedPercent: 0,
    newResetsAtIso: "2026-05-20T04:59:34.723Z",
  }, {
    title: "Primary reset",
    body: "The 5-hour Codex bucket looks restored.",
  }, settings, displayInfo);
  const primaryImagePathIndex = primaryArgs.indexOf("-ImagePath");
  assert.notEqual(primaryImagePathIndex, -1);
  assert.equal(primaryArgs[primaryImagePathIndex + 1], settings.billboardImageAsset.resolvedPath);

  console.log("auth expired notification regression passed");
} catch (error) {
  console.error("auth expired notification regression failed");
  console.error(error.message);
  process.exit(1);
}
