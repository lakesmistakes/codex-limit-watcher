const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { AUTH_EXPIRED_BODY, AUTH_EXPIRED_TITLE } = require("./authExpired");
const { normalizeDisplaySettings, buildDisplayInfo } = require("./displayTime");

function notify(event, config, rootDir, logWarning = () => {}) {
  const settings = normalizeNotificationSettings(config, rootDir, logWarning);
  const message = getEventMessage(event.type, settings);
  const displayInfo = buildDisplayInfo(event.newResetsAtIso, settings.display, new Date());
  const timing = {
    notificationStart: displayInfo.triggeredAtRaw,
    soundSpawnedAt: null,
    toastSpawnedAt: null,
    billboardSpawnedAt: null,
    billboardReadyAt: null,
    soundBillboardDelayMs: null,
  };
  const channelPlans = [];

  if (settings.soundEnabled && settings.soundAsset.exists) {
    channelPlans.push({ name: "sound", args: buildSoundArgs(rootDir, message, settings) });
  }

  if (settings.toastEnabled) {
    channelPlans.push({ name: "toast", args: buildToastArgs(rootDir, message) });
  }

  if (settings.billboardEnabled && shouldShowBillboard(event.type)) {
    channelPlans.push({
      name: "billboard",
      args: buildBillboardArgs(rootDir, event, message, settings, displayInfo),
    });
  }

  for (const channelPlan of channelPlans) {
    const spawnedAt = new Date().toISOString();
    timing[`${channelPlan.name}SpawnedAt`] = spawnedAt;
    spawnDetachedPowerShell(channelPlan.args);
  }

  timing.soundBillboardDelayMs = diffIsoMs(timing.soundSpawnedAt, timing.billboardSpawnedAt);
  return { timing, display: displayInfo };
}

function normalizeNotificationSettings(config, rootDir, logWarning = () => {}) {
  const notifications = config.notifications || {};
  const billboard = config.billboard || {};
  const display = normalizeDisplaySettings(config.display || {}, logWarning);
  const soundAsset = resolveAsset(notifications.soundFile, rootDir, "sound file", logWarning);
  const billboardImageAsset = resolveAsset(
    notifications.billboardImage,
    rootDir,
    "billboard image",
    logWarning,
    { includeImageMetadata: true },
  );
  const legacyDismissible = parseOptionalBoolean(billboard.dismissible);
  const maxWidth = numberOrDefault(billboard.maxWidth, 460);
  const maxHeight = numberOrDefault(billboard.maxHeight, 345);
  const autoSizeToImage = billboard.autoSizeToImage !== false;
  const fallbackWidth = numberOrDefault(billboard.width, maxWidth);
  const fallbackHeight = numberOrDefault(billboard.height, maxHeight);
  const position = enumOrDefault(
    billboard.position,
    ["center", "bottomRight", "bottomLeft", "topRight", "topLeft"],
    "bottomRight",
  );
  const screenMargin = numberOrDefault(billboard.screenMargin, 24);
  const windowSize = resolveBillboardWindowSize({
    autoSizeToImage,
    maxWidth,
    maxHeight,
    fallbackWidth,
    fallbackHeight,
    imageWidth: billboardImageAsset.width,
    imageHeight: billboardImageAsset.height,
  });

  return {
    toastEnabled: notifications.toastEnabled !== false,
    billboardEnabled: notifications.billboardEnabled !== false,
    soundEnabled: notifications.soundEnabled !== false,
    soundAsset,
    billboardImageAsset,
    primary5hTitle: notifications.primary5hTitle || "Codex 5-hour limit is back",
    primary5hMessage: notifications.primary5hMessage || "The 5-hour Codex bucket looks restored.",
    weeklyTitle: notifications.weeklyTitle || "Codex weekly limit is back",
    weeklyMessage: notifications.weeklyMessage || "The weekly Codex bucket looks restored.",
    earlyWeeklyTitle: notifications.earlyWeeklyTitle || "Early weekly reset detected",
    earlyWeeklyMessage: notifications.earlyWeeklyMessage || "Codex weekly usage dropped before the expected reset time.",
    display,
    billboard: {
      durationSeconds: numberOrDefault(billboard.durationSeconds, 30),
      alwaysOnTop: billboard.alwaysOnTop !== false,
      borderless: billboard.borderless !== false,
      showTaskbarIcon: billboard.showTaskbarIcon === true,
      mode: enumOrDefault(billboard.mode, ["imageOnly", "imageWithSmallBadge"], "imageWithSmallBadge"),
      fit: enumOrDefault(billboard.fit, ["contain", "fill", "stretch"], "contain"),
      autoSizeToImage,
      maxWidth,
      maxHeight,
      position,
      screenMargin,
      backgroundColor: typeof billboard.backgroundColor === "string" && billboard.backgroundColor.trim()
        ? billboard.backgroundColor.trim()
        : "#000000",
      showCustomDismissButton: billboard.showCustomDismissButton != null
        ? Boolean(billboard.showCustomDismissButton)
        : legacyDismissible === null ? false : legacyDismissible,
      clickToDismiss: billboard.clickToDismiss != null
        ? Boolean(billboard.clickToDismiss)
        : legacyDismissible === null ? true : legacyDismissible,
      badgeFontSize: numberOrDefault(billboard.badgeFontSize, 11),
      badgePadding: numberOrDefault(billboard.badgePadding, 8),
      badgeOpacity: opacityOrDefault(billboard.badgeOpacity, 0.72),
      width: windowSize.width,
      height: windowSize.height,
    },
  };
}

function getEventMessage(type, settings) {
  if (type === "authExpired") {
    return { title: AUTH_EXPIRED_TITLE, body: AUTH_EXPIRED_BODY };
  }
  if (type === "primary5h") {
    return { title: settings.primary5hTitle, body: settings.primary5hMessage };
  }
  if (type === "earlyWeekly") {
    return { title: settings.earlyWeeklyTitle, body: settings.earlyWeeklyMessage };
  }
  return { title: settings.weeklyTitle, body: settings.weeklyMessage };
}

function shouldShowBillboard(type) {
  return type === "weekly" || type === "earlyWeekly" || type === "primary5h" || type === "authExpired";
}

async function runNotificationTest({
  event,
  config,
  rootDir,
  configPath = null,
  channels = ["sound", "toast", "billboard"],
  billboardDurationSeconds = 5,
  toastVisibleSeconds = 4,
}) {
  const warnings = [];
  const notificationStartedAt = new Date();
  const settings = normalizeNotificationSettings(config, rootDir, (message) => warnings.push(message));
  const message = getEventMessage(event.type, settings);
  const requestedChannels = new Set(channels);
  const displayInfo = buildDisplayInfo(event.newResetsAtIso, settings.display, notificationStartedAt);
  const result = {
    loadedConfigPath: configPath,
    eventType: event.type,
    message,
    warnings,
    assets: {
      soundFile: settings.soundAsset,
      billboardImage: settings.billboardImageAsset,
    },
    billboardConfig: {
      borderless: settings.billboard.borderless,
      fit: settings.billboard.fit,
      mode: settings.billboard.mode,
      autoSizeToImage: settings.billboard.autoSizeToImage,
      maxWidth: settings.billboard.maxWidth,
      maxHeight: settings.billboard.maxHeight,
      position: settings.billboard.position,
      screenMargin: settings.billboard.screenMargin,
      backgroundColor: settings.billboard.backgroundColor,
      showTaskbarIcon: settings.billboard.showTaskbarIcon,
      showCustomDismissButton: settings.billboard.showCustomDismissButton,
      clickToDismiss: settings.billboard.clickToDismiss,
      badgeFontSize: settings.billboard.badgeFontSize,
      badgePadding: settings.billboard.badgePadding,
      badgeOpacity: settings.billboard.badgeOpacity,
      alwaysOnTop: settings.billboard.alwaysOnTop,
      finalWindowWidth: settings.billboard.width,
      finalWindowHeight: settings.billboard.height,
    },
    billboardPlacement: null,
    display: displayInfo,
    timing: {
      notificationStart: notificationStartedAt.toISOString(),
      soundSpawnedAt: null,
      toastSpawnedAt: null,
      billboardSpawnedAt: null,
      billboardReadyAt: null,
      soundBillboardDelayMs: null,
    },
    toast: createChannelResult(),
    sound: createChannelResult(),
    billboard: createChannelResult(),
  };
  const tasks = [];

  if (requestedChannels.has("sound")) {
    if (!settings.soundEnabled) {
      result.sound.error = "disabled in config";
    } else if (!settings.soundAsset.configuredPath) {
      result.sound.error = "no sound file configured";
    } else if (!settings.soundAsset.exists) {
      result.sound.error = `sound file missing: ${settings.soundAsset.configuredPath}`;
    } else {
      const spawnedAt = new Date().toISOString();
      result.timing.soundSpawnedAt = spawnedAt;
      tasks.push(
        executeChannel(buildSoundArgs(rootDir, message, settings), {
          expectStdoutToken: "SOUND_OK",
          spawnedAt,
        }).then((channelResult) => {
          result.sound = channelResult;
        }),
      );
    }
  }

  if (requestedChannels.has("toast")) {
    if (!settings.toastEnabled) {
      result.toast.error = "disabled in config";
    } else {
      const spawnedAt = new Date().toISOString();
      result.timing.toastSpawnedAt = spawnedAt;
      tasks.push(
        executeChannel(buildToastArgs(rootDir, message, toastVisibleSeconds), {
          expectStdoutToken: "TOAST_OK",
          spawnedAt,
        }).then((channelResult) => {
          result.toast = channelResult;
        }),
      );
    }
  }

  if (requestedChannels.has("billboard")) {
    if (!settings.billboardEnabled) {
      result.billboard.error = "disabled in config";
    } else if (!shouldShowBillboard(event.type)) {
      result.billboard.error = `billboard is not supported for event type: ${event.type}`;
    } else {
      const spawnedAt = new Date().toISOString();
      result.timing.billboardSpawnedAt = spawnedAt;
      tasks.push(
        executeChannel(
          buildBillboardArgs(rootDir, event, message, settings, displayInfo, {
            seconds: billboardDurationSeconds,
            emitReady: true,
          }),
          {
            expectStdoutToken: "BILLBOARD_READY",
            spawnedAt,
            metadataPrefix: "BILLBOARD_META ",
          },
        ).then((channelResult) => {
          result.billboard = channelResult;
        }),
      );
    }
  }

  await Promise.all(tasks);
  result.timing.billboardReadyAt = result.billboard.readyAt;
  result.timing.soundBillboardDelayMs = diffIsoMs(result.timing.soundSpawnedAt, result.timing.billboardSpawnedAt);
  result.billboardPlacement = result.billboard.metadata || null;
  if (result.billboardPlacement) {
    result.billboardConfig.finalWindowWidth = result.billboardPlacement.windowWidth ?? result.billboardConfig.finalWindowWidth;
    result.billboardConfig.finalWindowHeight = result.billboardPlacement.windowHeight ?? result.billboardConfig.finalWindowHeight;
    result.billboardConfig.finalWindowLeft = result.billboardPlacement.windowLeft ?? null;
    result.billboardConfig.finalWindowTop = result.billboardPlacement.windowTop ?? null;
    result.billboardConfig.screenWorkingArea = result.billboardPlacement.screenWorkingArea || null;
  }
  return result;
}

function resolveAsset(configPath, rootDir, label, logWarning, options = {}) {
  if (!configPath) {
    return withImageMetadata({ configuredPath: null, resolvedPath: null, exists: false }, options);
  }

  const resolvedPath = path.resolve(rootDir, configPath);
  const exists = fs.existsSync(resolvedPath);
  if (!exists) logWarning(`${label} missing: ${configPath}`);
  return withImageMetadata({ configuredPath: configPath, resolvedPath, exists }, options);
}

function withImageMetadata(asset, options) {
  if (!options.includeImageMetadata) {
    return asset;
  }

  if (!asset.exists || !asset.resolvedPath) {
    return { ...asset, format: null, width: null, height: null };
  }

  return { ...asset, ...readImageMetadata(asset.resolvedPath) };
}

function createChannelResult() {
  return {
    attempted: false,
    success: false,
    error: null,
    exitCode: null,
    stdout: "",
    stderr: "",
    spawnedAt: null,
    readyAt: null,
    metadata: null,
  };
}

async function executeChannel(args, { expectStdoutToken, spawnedAt = null, metadataPrefix = null } = {}) {
  const outcome = await runPowerShell(args, { watchToken: expectStdoutToken });
  const result = {
    attempted: true,
    success: false,
    error: null,
    exitCode: outcome.exitCode,
    stdout: outcome.stdout,
    stderr: outcome.stderr,
    spawnedAt,
    readyAt: outcome.tokenSeenAt,
    metadata: metadataPrefix ? extractPrefixedJson(outcome.stdout, metadataPrefix) : null,
  };

  if (outcome.error) {
    result.error = outcome.error;
    return result;
  }

  if (outcome.exitCode !== 0) {
    result.error = firstNonEmpty(outcome.stderr, outcome.stdout, `PowerShell exited with code ${outcome.exitCode}`);
    return result;
  }

  if (expectStdoutToken && !outcome.stdout.includes(expectStdoutToken)) {
    result.error = `missing success token: ${expectStdoutToken}`;
    return result;
  }

  result.success = true;
  return result;
}

function runPowerShell(args, { watchToken } = {}) {
  return new Promise((resolve) => {
    const child = spawn("powershell.exe", args, { windowsHide: true });
    let stdout = "";
    let stderr = "";
    let settled = false;
    let tokenSeenAt = null;

    child.stdout.on("data", (chunk) => {
      stdout += String(chunk);
      if (!tokenSeenAt && watchToken && stdout.includes(watchToken)) {
        tokenSeenAt = new Date().toISOString();
      }
    });
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
    });
    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      resolve({
        exitCode: null,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        error: error.message,
        tokenSeenAt,
      });
    });
    child.on("close", (exitCode) => {
      if (settled) return;
      settled = true;
      resolve({
        exitCode,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        error: null,
        tokenSeenAt,
      });
    });
  });
}

function spawnDetachedPowerShell(args) {
  spawn("powershell.exe", args, { detached: true, stdio: "ignore", windowsHide: true }).unref();
}

function buildSoundArgs(rootDir, message, settings) {
  return [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(rootDir, "scripts", "notify.ps1"),
    "-Title",
    message.title,
    "-Body",
    message.body,
    "-SoundFile",
    settings.soundAsset.resolvedPath,
    "-PlaySoundOnly",
    "True",
  ];
}

function buildToastArgs(rootDir, message, visibleSeconds = 12) {
  return [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(rootDir, "scripts", "notify.ps1"),
    "-Title",
    message.title,
    "-Body",
    message.body,
    "-ToastEnabled",
    "True",
    "-VisibleSeconds",
    String(visibleSeconds),
  ];
}

function buildBillboardArgs(rootDir, event, message, settings, displayInfo, overrides = {}) {
  const seconds = overrides.seconds ?? settings.billboard.durationSeconds;
  const emitReady = Boolean(overrides.emitReady);
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Sta",
    "-File",
    path.join(rootDir, "scripts", "billboard.ps1"),
    "-Title",
    message.title,
    "-Message",
    message.body,
    "-Bucket",
    event.bucket || "unknown",
    "-OldUsed",
    String(event.oldUsedPercent ?? "unknown"),
    "-NewUsed",
    String(event.newUsedPercent ?? "unknown"),
    "-ResetTime",
    event.newResetsAtIso || "unknown",
    "-ScheduledText",
    displayInfo.formattedResetTimestamp,
    "-TriggeredText",
    displayInfo.formattedTriggeredTimestamp,
    "-Seconds",
    String(seconds),
    "-Width",
    String(settings.billboard.width),
    "-Height",
    String(settings.billboard.height),
    "-AlwaysOnTop",
    String(Boolean(settings.billboard.alwaysOnTop)),
    "-Borderless",
    String(Boolean(settings.billboard.borderless)),
    "-ShowTaskbarIcon",
    String(Boolean(settings.billboard.showTaskbarIcon)),
    "-Mode",
    settings.billboard.mode,
    "-Fit",
    settings.billboard.fit,
    "-Position",
    settings.billboard.position,
    "-ScreenMargin",
    String(settings.billboard.screenMargin),
    "-BackgroundColor",
    settings.billboard.backgroundColor,
    "-BadgeFontSize",
    String(settings.billboard.badgeFontSize),
    "-BadgePadding",
    String(settings.billboard.badgePadding),
    "-BadgeOpacity",
    String(settings.billboard.badgeOpacity),
    "-ShowCustomDismissButton",
    String(Boolean(settings.billboard.showCustomDismissButton)),
    "-ClickToDismiss",
    String(Boolean(settings.billboard.clickToDismiss)),
    "-EmitReady",
    String(emitReady),
  ];
  if (event.type !== "authExpired" && settings.billboardImageAsset.exists) {
    args.push("-ImagePath", settings.billboardImageAsset.resolvedPath);
  }
  return args;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (value) return value;
  }
  return null;
}

function extractPrefixedJson(stdout, prefix) {
  if (!stdout) return null;
  const line = stdout.split(/\r?\n/).find((entry) => entry.startsWith(prefix));
  if (!line) return null;
  try {
    return JSON.parse(line.slice(prefix.length));
  } catch {
    return null;
  }
}

function readImageMetadata(filePath) {
  try {
    const buffer = fs.readFileSync(filePath);
    if (buffer.length >= 24 && buffer[0] === 0x89 && buffer.toString("ascii", 1, 4) === "PNG") {
      return {
        format: "png",
        width: buffer.readUInt32BE(16),
        height: buffer.readUInt32BE(20),
      };
    }
    if (buffer.length >= 10 && (buffer.toString("ascii", 0, 6) === "GIF87a" || buffer.toString("ascii", 0, 6) === "GIF89a")) {
      return {
        format: "gif",
        width: buffer.readUInt16LE(6),
        height: buffer.readUInt16LE(8),
      };
    }
    if (buffer.length >= 26 && buffer.toString("ascii", 0, 2) === "BM") {
      return {
        format: "bmp",
        width: buffer.readUInt32LE(18),
        height: Math.abs(buffer.readInt32LE(22)),
      };
    }
    if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
      let offset = 2;
      while (offset + 8 < buffer.length) {
        if (buffer[offset] !== 0xff) break;
        const marker = buffer[offset + 1];
        const size = buffer.readUInt16BE(offset + 2);
        if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
          return {
            format: "jpeg",
            width: buffer.readUInt16BE(offset + 7),
            height: buffer.readUInt16BE(offset + 5),
          };
        }
        if (size < 2) break;
        offset += 2 + size;
      }
    }
  } catch {
    return { format: null, width: null, height: null };
  }

  return { format: null, width: null, height: null };
}

function parseOptionalBoolean(value) {
  if (value == null) return null;
  return value !== false;
}

function enumOrDefault(value, allowed, fallback) {
  return allowed.includes(value) ? value : fallback;
}

function resolveBillboardWindowSize({
  autoSizeToImage,
  maxWidth,
  maxHeight,
  fallbackWidth,
  fallbackHeight,
  imageWidth,
  imageHeight,
}) {
  if (!autoSizeToImage || !Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) || imageWidth <= 0 || imageHeight <= 0) {
    return {
      width: Math.max(1, Math.round(fallbackWidth)),
      height: Math.max(1, Math.round(fallbackHeight)),
    };
  }

  const scale = Math.min(1, maxWidth / imageWidth, maxHeight / imageHeight);
  return {
    width: Math.max(1, Math.round(imageWidth * scale)),
    height: Math.max(1, Math.round(imageHeight * scale)),
  };
}

function diffIsoMs(a, b) {
  if (!a || !b) return null;
  const left = Date.parse(a);
  const right = Date.parse(b);
  if (!Number.isFinite(left) || !Number.isFinite(right)) return null;
  return right - left;
}

function opacityOrDefault(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(1, Math.max(0, number));
}

function numberOrDefault(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

module.exports = {
  buildBillboardArgs,
  normalizeNotificationSettings,
  notify,
  runNotificationTest,
  shouldShowBillboard,
};
