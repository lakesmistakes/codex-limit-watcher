const { notify } = require("./notifier");
const path = require("node:path");
const fs = require("node:fs");

const rootDir = path.resolve(__dirname, "..");
const config = JSON.parse(fs.readFileSync(path.join(rootDir, "config.json"), "utf8"));
const argv = process.argv.slice(2);

const messageIndex = argv.indexOf("--message");
const inIndex = argv.indexOf("--in");
const atIndex = argv.indexOf("--at");
const message = messageIndex >= 0 ? argv[messageIndex + 1] : "Manual Codex limit reminder";
const delayMs = inIndex >= 0 ? parseDuration(argv[inIndex + 1]) : atIndex >= 0 ? Math.max(0, Date.parse(argv[atIndex + 1]) - Date.now()) : null;

if (delayMs == null || Number.isNaN(delayMs)) {
  console.log("Usage: npm run manual-reminder -- --in 5h --message \"Check Codex limits\"");
  console.log("   or: npm run manual-reminder -- --at \"2026-05-17 09:00\" --message \"Check Codex limits\"");
  process.exit(1);
}

console.log(`Manual reminder armed for ${Math.round(delayMs / 1000)} seconds from now. Keep this terminal open.`);
setTimeout(() => {
  notify({
    type: "primary5h",
    bucket: "manual",
    oldUsedPercent: "unknown",
    newUsedPercent: "unknown",
    newResetsAtIso: new Date().toISOString(),
  }, {
    ...config,
    notifications: {
      ...(config.notifications || {}),
      primary5hTitle: "Codex manual reminder",
      primary5hMessage: message,
      billboardEnabled: false,
    },
  }, rootDir, (warning) => console.warn(`Warning: ${warning}`));
  console.log("Manual reminder fired.");
}, delayMs);

function parseDuration(value) {
  const match = /^(\d+)(s|m|h|d)$/i.exec(String(value || ""));
  if (!match) return null;
  const amount = Number(match[1]);
  const unit = match[2].toLowerCase();
  return amount * ({ s: 1000, m: 60000, h: 3600000, d: 86400000 }[unit]);
}
