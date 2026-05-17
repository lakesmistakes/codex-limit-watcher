const FIVE_HOURS_MINS = 300;
const WEEK_MINS = 10080;

function normalizeRateLimits(response) {
  const snapshot = selectCodexSnapshot(response);
  const primary = normalizeWindow(snapshot && snapshot.primary, "primary");
  const secondary = normalizeWindow(snapshot && snapshot.secondary, "secondary");

  return {
    source: "codex-app-server",
    limitId: snapshot && snapshot.limitId || null,
    limitName: snapshot && snapshot.limitName || null,
    planType: snapshot && snapshot.planType || null,
    rateLimitReachedType: snapshot && snapshot.rateLimitReachedType || null,
    credits: snapshot && snapshot.credits ? {
      hasCredits: Boolean(snapshot.credits.hasCredits),
      unlimited: Boolean(snapshot.credits.unlimited),
      balance: snapshot.credits.balance == null ? null : String(snapshot.credits.balance),
    } : null,
    primary,
    secondary,
    primaryMappingConfirmed: confirmsWindow(primary, FIVE_HOURS_MINS, "primary"),
    secondaryMappingConfirmed: confirmsWindow(secondary, WEEK_MINS, "secondary"),
    rawSafeShape: safeShape(response),
  };
}

function selectCodexSnapshot(response) {
  if (!response || typeof response !== "object") return null;
  const byId = response.rateLimitsByLimitId;
  if (byId && byId.codex) return byId.codex;
  return response.rateLimits || null;
}

function normalizeWindow(window, label) {
  if (!window || typeof window !== "object") return null;
  const usedPercent = asNumber(window.usedPercent);
  const remainingPercent = usedPercent == null ? null : clamp(100 - usedPercent, 0, 100);
  return {
    label,
    usedPercent,
    remainingPercent,
    windowDurationMins: asNumber(window.windowDurationMins),
    resetsAt: asNumber(window.resetsAt),
    resetsAtIso: window.resetsAt ? new Date(window.resetsAt * 1000).toISOString() : null,
  };
}

function confirmsWindow(window, expectedMins, fallbackLabel) {
  if (!window) return false;
  if (window.windowDurationMins === expectedMins) return true;
  return String(window.label || "").toLowerCase().includes(fallbackLabel);
}

function detectEvents(previous, current, config) {
  if (!previous || !current) return [];
  const events = [];
  if (config.notifyPrimary5h && current.primaryMappingConfirmed) {
    maybePush(events, "primary5h", "5-hour", previous.primary, current.primary, config, false);
  }
  if (config.notifyWeekly && current.secondaryMappingConfirmed) {
    const early = previous.secondary && current.secondary && previous.secondary.resetsAt &&
      current.secondary.resetsAt && current.secondary.resetsAt !== previous.secondary.resetsAt &&
      Date.now() / 1000 < previous.secondary.resetsAt - 300;
    maybePush(events, early ? "earlyWeekly" : "weekly", "weekly", previous.secondary, current.secondary, config, early);
  }
  return events;
}

function maybePush(events, type, bucket, oldWindow, newWindow, config, early) {
  if (!oldWindow || !newWindow) return;
  const usedDrop = oldWindow.usedPercent != null && newWindow.usedPercent != null &&
    oldWindow.usedPercent - newWindow.usedPercent >= 25;
  const reachesThreshold = newWindow.remainingPercent != null &&
    newWindow.remainingPercent >= Number(config.notifyThresholdRemaining || 100);
  const resetAdvanced = oldWindow.resetsAt && newWindow.resetsAt && newWindow.resetsAt > oldWindow.resetsAt;
  const becameUsable = oldWindow.remainingPercent === 0 && newWindow.remainingPercent > 0;

  if (usedDrop || reachesThreshold || resetAdvanced || becameUsable) {
    events.push({
      type,
      bucket,
      early,
      oldUsedPercent: oldWindow.usedPercent,
      newUsedPercent: newWindow.usedPercent,
      oldRemainingPercent: oldWindow.remainingPercent,
      newRemainingPercent: newWindow.remainingPercent,
      oldResetsAt: oldWindow.resetsAt,
      newResetsAt: newWindow.resetsAt,
      newResetsAtIso: newWindow.resetsAtIso,
      reasons: { usedDrop, reachesThreshold, resetAdvanced, becameUsable },
    });
  }
}

function safeShape(value) {
  if (Array.isArray(value)) return value.map(safeShape);
  if (!value || typeof value !== "object") return typeof value;
  const out = {};
  for (const [key, child] of Object.entries(value)) {
    if (/token|secret|cookie|auth|key|email|account/i.test(key) && typeof child === "string") {
      out[key] = "[REDACTED:string]";
    } else if (child == null) {
      out[key] = null;
    } else if (typeof child === "object") {
      out[key] = safeShape(child);
    } else {
      out[key] = `${typeof child}:${String(child).slice(0, 80)}`;
    }
  }
  return out;
}

function compactWindow(window) {
  if (!window) return "n/a";
  return `used=${fmt(window.usedPercent)} remaining=${fmt(window.remainingPercent)} reset=${window.resetsAtIso || "n/a"}`;
}

function asNumber(value) {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function fmt(value) {
  return value == null ? "n/a" : `${value}%`;
}

module.exports = {
  FIVE_HOURS_MINS,
  WEEK_MINS,
  normalizeRateLimits,
  detectEvents,
  safeShape,
  compactWindow,
};
