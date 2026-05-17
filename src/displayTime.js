function normalizeDisplaySettings(display = {}, logWarning = () => {}) {
  const configuredTimeZone = typeof display.timeZone === "string" && display.timeZone.trim()
    ? display.timeZone.trim()
    : "local";
  const resetTimeFormat = normalizeFormat(display.resetTimeFormat, "weekdayTime");
  const triggeredTimeFormat = normalizeFormat(display.triggeredTimeFormat, "dateTime");

  let intlTimeZone;
  try {
    intlTimeZone = configuredTimeZone === "local" ? undefined : configuredTimeZone;
    new Intl.DateTimeFormat("en-US", { timeZone: intlTimeZone, hour: "numeric" }).format(new Date());
  } catch {
    logWarning(`invalid display time zone: ${configuredTimeZone}; using local time`);
    intlTimeZone = undefined;
  }

  const resolvedTimeZone = new Intl.DateTimeFormat("en-US", { timeZone: intlTimeZone, hour: "numeric" })
    .resolvedOptions().timeZone || "local";

  return {
    timeZone: configuredTimeZone,
    timeZoneUsed: resolvedTimeZone,
    intlTimeZone,
    resetTimeFormat,
    triggeredTimeFormat,
  };
}

function buildDisplayInfo(rawResetTimestamp, displaySettings, triggeredAt = new Date()) {
  return {
    rawResetTimestamp: rawResetTimestamp || null,
    formattedResetTimestamp: formatLabel("Scheduled", rawResetTimestamp, displaySettings.resetTimeFormat, displaySettings),
    triggeredAtRaw: isValidDate(triggeredAt) ? triggeredAt.toISOString() : null,
    formattedTriggeredTimestamp: formatLabel("Triggered", triggeredAt, displaySettings.triggeredTimeFormat, displaySettings),
    timeZoneUsed: displaySettings.timeZoneUsed,
    resetTimeFormat: displaySettings.resetTimeFormat,
    triggeredTimeFormat: displaySettings.triggeredTimeFormat,
  };
}

function formatLabel(prefix, value, format, displaySettings) {
  const date = value instanceof Date ? value : new Date(value);
  if (!isValidDate(date)) {
    return `${prefix} time unavailable`;
  }

  return `${prefix} ${formatValue(date, format, displaySettings)}`;
}

function formatValue(date, format, displaySettings) {
  if (format === "weekdayTime") {
    const weekday = formatParts(date, { weekday: "long" }, displaySettings);
    const time = formatParts(date, { hour: "numeric", minute: "2-digit" }, displaySettings);
    return `${weekday} at ${time}`;
  }

  const dateText = formatParts(date, { month: "long", day: "numeric", year: "numeric" }, displaySettings);
  const timeText = formatParts(date, { hour: "numeric", minute: "2-digit" }, displaySettings);
  return `${dateText} at ${timeText}`;
}

function formatParts(date, options, displaySettings) {
  return new Intl.DateTimeFormat("en-US", {
    ...options,
    timeZone: displaySettings.intlTimeZone,
  }).format(date);
}

function normalizeFormat(value, fallback) {
  return value === "weekdayTime" || value === "dateTime" ? value : fallback;
}

function isValidDate(value) {
  return value instanceof Date && Number.isFinite(value.getTime());
}

module.exports = {
  normalizeDisplaySettings,
  buildDisplayInfo,
};
