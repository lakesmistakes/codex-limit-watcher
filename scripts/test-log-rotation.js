const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  appendAppLog,
  MAX_APP_LOG_BYTES,
  ROTATED_APP_LOG_COPIES,
} = require("../src/logging");

function main() {
  assert.equal(MAX_APP_LOG_BYTES, 2 * 1024 * 1024);
  assert.equal(ROTATED_APP_LOG_COPIES, 4);

  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-limit-watcher-log-"));

  try {
    provesDefaultAppLogRotates(rootDir);
    provesNonDefaultLogsAreNotRotated(rootDir);
    console.log("log rotation regression passed");
  } finally {
    removeTree(rootDir);
  }
}

function provesDefaultAppLogRotates(rootDir) {
  const logPath = path.join(rootDir, "logs", "codex-limit-watcher.log");
  const backupPath = path.join(rootDir, "logs", "config-backups", "config-keep.json");

  writeFile(logPath, "x".repeat(MAX_APP_LOG_BYTES + 1));
  writeFile(`${logPath}.1`, "old-one");
  writeFile(`${logPath}.2`, "old-two");
  writeFile(`${logPath}.3`, "old-three");
  writeFile(`${logPath}.4`, "old-four");
  writeFile(backupPath, "{\"keep\":true}");

  appendAppLog({}, rootDir, { source: "test", message: "rotated" });

  const current = JSON.parse(fs.readFileSync(logPath, "utf8"));
  assert.equal(current.source, "test");
  assert.equal(current.message, "rotated");
  assert.equal(fs.readFileSync(`${logPath}.1`, "utf8").length, MAX_APP_LOG_BYTES + 1);
  assert.equal(fs.readFileSync(`${logPath}.2`, "utf8"), "old-one");
  assert.equal(fs.readFileSync(`${logPath}.3`, "utf8"), "old-two");
  assert.equal(fs.readFileSync(`${logPath}.4`, "utf8"), "old-three");
  assert.equal(fs.readFileSync(backupPath, "utf8"), "{\"keep\":true}");
}

function provesNonDefaultLogsAreNotRotated(rootDir) {
  const logPath = path.join(rootDir, "logs", "other.log");

  writeFile(logPath, "y".repeat(MAX_APP_LOG_BYTES + 1));
  appendAppLog({ logPath: "logs/other.log" }, rootDir, { source: "test", message: "custom" });

  assert.equal(fs.existsSync(`${logPath}.1`), false);
  assert.match(fs.readFileSync(logPath, "utf8"), /"message":"custom"/);
}

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents);
}

function removeTree(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return;
  }

  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const entryPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      removeTree(entryPath);
    } else {
      fs.chmodSync(entryPath, 0o666);
      fs.unlinkSync(entryPath);
    }
  }

  fs.rmdirSync(dirPath);
}

main();
