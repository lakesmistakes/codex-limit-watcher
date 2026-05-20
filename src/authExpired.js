const AUTH_EXPIRED_TITLE = "Codex auth expired";
const AUTH_EXPIRED_BODY = "Open Codex and sign in again. Limit Watcher cannot read usage right now.";
const AUTH_EXPIRED_SIGNALS = [
  "401 Unauthorized",
  "token_invalidated",
  "Your authentication token has been invalidated",
  "signing in again",
];

function getAuthExpiredState(error, suppressionActive = false) {
  const matchedSignals = matchAuthExpiredSignals(error);
  if (matchedSignals.length === 0) {
    return {
      authExpired: false,
      shouldNotify: false,
      nextSuppressed: suppressionActive,
      matchedSignals: [],
    };
  }

  return {
    authExpired: true,
    shouldNotify: !suppressionActive,
    nextSuppressed: true,
    matchedSignals,
  };
}

function createAuthExpiredNotificationEvent(now = new Date()) {
  return {
    type: "authExpired",
    bucket: "auth",
    newResetsAtIso: now.toISOString(),
  };
}

function matchAuthExpiredSignals(error) {
  const combined = collectAuthExpiredText(error).toLowerCase();
  if (!combined) {
    return [];
  }

  return AUTH_EXPIRED_SIGNALS.filter((signal) => combined.includes(signal.toLowerCase()));
}

function collectAuthExpiredText(error) {
  const pieces = [];
  pushText(pieces, error && error.message);

  const diagnostics = error && error.appServerDiagnostics ? error.appServerDiagnostics : null;
  if (diagnostics) {
    pushMany(pieces, diagnostics.recentStdout);
    pushMany(pieces, diagnostics.recentStderr);
    if (diagnostics.childError && diagnostics.childError.message) {
      pushText(pieces, diagnostics.childError.message);
    }
  }

  return pieces.join("\n");
}

function pushMany(target, values) {
  if (!Array.isArray(values)) {
    return;
  }

  for (const value of values) {
    pushText(target, value);
  }
}

function pushText(target, value) {
  if (typeof value !== "string") {
    return;
  }

  const trimmed = value.trim();
  if (trimmed) {
    target.push(trimmed);
  }
}

module.exports = {
  AUTH_EXPIRED_BODY,
  AUTH_EXPIRED_TITLE,
  createAuthExpiredNotificationEvent,
  getAuthExpiredState,
};
