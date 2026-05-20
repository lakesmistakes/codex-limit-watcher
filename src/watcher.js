const path = require("node:path");
const { AUTH_EXPIRED_BODY, createAuthExpiredNotificationEvent, getAuthExpiredState } = require("./authExpired");
process.noDeprecation = true;
const { AppServerClient } = require("./appServerClient");
const { loadConfig } = require("./config");
const { appendAppLog, ensureAppLogDir } = require("./logging");
const { normalizeRateLimits, detectEvents, compactWindow } = require("./rateLimits");
const { notify, runNotificationTest } = require("./notifier");

const rootDir = path.resolve(__dirname, "..");
const argv = process.argv.slice(2);
const args = new Set(argv);

main().catch((error) => {
  console.error(error.message);
  printAppServerDiagnostics(error.appServerDiagnostics);
  process.exitCode = 1;
});

async function main() {
  const { config, configPath } = loadConfig(rootDir);
  ensureAppLogDir(config, rootDir);

  const notificationCommand = readNotificationCommand();
  if (notificationCommand) {
    await runNotificationCommand(notificationCommand, config, configPath);
    return;
  }

  const state = {
    previous: null,
    successfulReads: 0,
    pendingCounts: new Map(),
    lastNotifiedAt: new Map(),
    authExpiredNotificationSuppressed: false,
  };

  const client = new AppServerClient({ codexCommand: config.codexCommand });
  let init;
  try {
    init = await client.start();
  } catch (error) {
    const handled = recordAppServerError({
      client,
      config,
      error,
      state,
      extraEntry: { mode: "manual-reminder-fallback" },
    });
    const wrapped = handled.authExpired
      ? new Error(`Codex auth expired. ${AUTH_EXPIRED_BODY}`)
      : new Error(`app-server did not start. Use manual fallback: npm run manual-reminder -- --in 5h --message "Check Codex limits"`);
    wrapped.appServerDiagnostics = handled.diagnostics;
    throw wrapped;
  }

  console.log(`Codex Limit Watcher started (${init.platformOs}; ${init.userAgent}).`);
  console.log("Press Ctrl+C to stop.");

  process.on("SIGINT", () => {
    client.stop();
    process.exit(0);
  });

  const runOnce = async () => {
    const raw = await client.readRateLimits();
    const current = normalizeRateLimits(raw);
    state.authExpiredNotificationSuppressed = false;
    state.successfulReads += 1;

    if (args.has("--log-raw-shape")) {
      console.log(JSON.stringify(current.rawSafeShape, null, 2));
    }

    const events = state.successfulReads >= Number(config.requireConsecutiveReads || 2)
      ? detectEvents(state.previous, current, config)
      : [];
    const fired = [];

    for (const event of events) {
      const key = `${event.type}:${event.bucket}`;
      const count = (state.pendingCounts.get(key) || 0) + 1;
      state.pendingCounts.set(key, count);
      if (count < Number(config.requireConsecutiveReads || 2)) continue;
      if (isCoolingDown(key, state, config) || inQuietHours(config)) continue;
      notify(event, config, rootDir, (message) => log(config, { source: "notifications", level: "warn", warning: message }));
      state.lastNotifiedAt.set(key, Date.now());
      state.pendingCounts.set(key, 0);
      fired.push(event.type);
    }

    if (!events.length) state.pendingCounts.clear();

    log(config, {
      source: current.source,
      limitId: current.limitId,
      planType: current.planType,
      primary: compactWindow(current.primary),
      primaryMappingConfirmed: current.primaryMappingConfirmed,
      secondary: compactWindow(current.secondary),
      secondaryMappingConfirmed: current.secondaryMappingConfirmed,
      rateLimitReachedType: current.rateLimitReachedType,
      notificationFired: fired,
    });

    console.log(`${new Date().toLocaleString()} primary ${compactWindow(current.primary)} | secondary ${compactWindow(current.secondary)} fired=${fired.join(",") || "none"}`);
    state.previous = current;
  };

  await runOnce();
  if (args.has("--once")) {
    client.stop();
    return;
  }

  setInterval(() => {
    runOnce().catch((error) => {
      state.successfulReads = 0;
      const handled = recordAppServerError({ client, config, error, state });
      if (handled.readableMessage) {
        console.error(handled.readableMessage);
      }
      console.error(error.message);
      printAppServerDiagnostics(handled.diagnostics);
    });
  }, Math.max(30, Number(config.pollEverySeconds || 300)) * 1000);
}

function log(config, entry) {
  appendAppLog(config, rootDir, entry);
}

function isCoolingDown(key, state, config) {
  const last = state.lastNotifiedAt.get(key);
  if (!last) return false;
  return Date.now() - last < Number(config.notificationCooldownSeconds || 1800) * 1000;
}

function inQuietHours(config) {
  if (!config.quietHours) return false;
  const start = config.quietHours.start;
  const end = config.quietHours.end;
  if (!start || !end) return false;
  const now = minutes(new Date());
  const a = parseTime(start);
  const b = parseTime(end);
  if (a == null || b == null) return false;
  return a <= b ? now >= a && now < b : now >= a || now < b;
}

function parseTime(value) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(value));
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function minutes(date) {
  return date.getHours() * 60 + date.getMinutes();
}

function readOption(name) {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : null;
}

function readNotificationCommand() {
  if (args.has("--diagnose-notifications")) return { mode: "diagnose-notifications" };
  if (args.has("--test-sound")) return { mode: "test-sound" };
  if (args.has("--test-toast")) return { mode: "test-toast" };
  if (args.has("--test-billboard")) return { mode: "test-billboard" };

  const testNotificationType = readOption("--test-notification");
  if (testNotificationType) {
    return { mode: "test-notification", type: testNotificationType };
  }

  return null;
}

async function runNotificationCommand(command, config, configPath) {
  const normalizedType = command.mode === "test-notification"
    ? normalizeTestType(command.type)
    : "weekly";

  if (!normalizedType) {
    throw new Error("Use --test-notification primary, weekly, or early-weekly");
  }

  const channelMap = {
    "diagnose-notifications": ["sound", "toast", "billboard"],
    "test-sound": ["sound"],
    "test-toast": ["toast"],
    "test-billboard": ["billboard"],
    "test-notification": ["sound", "toast", "billboard"],
  };
  const event = buildTestEvent(normalizedType);
  const result = await runNotificationTest({
    event,
    config,
    rootDir,
    configPath,
    channels: channelMap[command.mode],
    billboardDurationSeconds: 5,
    toastVisibleSeconds: 4,
  });

  log(config, {
    source: "notifications",
    mode: command.mode,
    requestedType: command.type || null,
    notificationTest: result,
  });
  printNotificationResult(command, result);
}

function buildTestEvent(type) {
  return {
    type,
    bucket: type === "primary5h" ? "5-hour" : "weekly",
    oldUsedPercent: type === "primary5h" ? 100 : 99,
    newUsedPercent: type === "primary5h" ? 0 : 5,
    newResetsAtIso: new Date().toISOString(),
  };
}

function printNotificationResult(command, result) {
  console.log(JSON.stringify(result, null, 2));
  const channelNames = ["sound", "toast", "billboard"];
  const succeeded = [];
  const failed = [];

  for (const channelName of channelNames) {
    const channel = result[channelName];
    if (channel.attempted && channel.success) {
      succeeded.push(channelName);
    } else if (channel.error) {
      failed.push(`${channelName}: ${channel.error}`);
    }
  }

  if (succeeded.length > 0) {
    console.log(`Notification ${command.mode} succeeded for: ${succeeded.join(", ")}`);
  }
  if (failed.length > 0) {
    console.error(`Notification ${command.mode} issues: ${failed.join(" | ")}`);
  }
  if (succeeded.length === 0) {
    process.exitCode = 1;
  }
}

function normalizeTestType(type) {
  if (type === "primary") return "primary5h";
  if (type === "weekly") return "weekly";
  if (type === "early-weekly") return "earlyWeekly";
  return null;
}

function getAppServerDiagnostics(client, error) {
  if (error && error.appServerDiagnostics) {
    return error.appServerDiagnostics;
  }
  return client.getDiagnostics();
}

function recordAppServerError({ client, config, error, state, extraEntry = {} }) {
  const diagnostics = getAppServerDiagnostics(client, error);
  const authExpiredState = getAuthExpiredState(error, state.authExpiredNotificationSuppressed);
  if (authExpiredState.authExpired) {
    state.authExpiredNotificationSuppressed = authExpiredState.nextSuppressed;
    if (authExpiredState.shouldNotify) {
      notify(
        createAuthExpiredNotificationEvent(),
        config,
        rootDir,
        (message) => log(config, { source: "notifications", level: "warn", warning: message }),
      );
    }
  }

  const readableMessage = authExpiredState.authExpired
    ? authExpiredState.shouldNotify
      ? `Codex auth expired. ${AUTH_EXPIRED_BODY}`
      : `Codex auth is still expired. Notification already sent. ${AUTH_EXPIRED_BODY}`
    : null;

  log(config, {
    source: "codex-app-server",
    error: error.message,
    notificationFired: authExpiredState.shouldNotify ? ["authExpired"] : [],
    authExpired: authExpiredState.authExpired,
    authExpiredNotificationSuppressed: authExpiredState.authExpired && !authExpiredState.shouldNotify,
    authExpiredSignals: authExpiredState.matchedSignals,
    readableMessage,
    appServerDiagnostics: diagnostics,
    ...extraEntry,
  });

  return {
    diagnostics,
    authExpired: authExpiredState.authExpired,
    readableMessage,
  };
}

function printAppServerDiagnostics(diagnostics) {
  if (!diagnostics) return;
  console.error("App-server diagnostics:");
  console.error(JSON.stringify(diagnostics, null, 2));
}
