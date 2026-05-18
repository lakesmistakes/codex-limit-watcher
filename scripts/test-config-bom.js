const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { readJsonFile } = require("../src/config");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-limit-watcher-config-"));
const file = path.join(dir, "config.json");

try {
  fs.writeFileSync(file, "\uFEFF{\"billboard\":{\"maxWidth\":400,\"maxHeight\":300}}", "utf8");
  const parsed = readJsonFile(file);
  assert.equal(parsed.billboard.maxWidth, 400);
  assert.equal(parsed.billboard.maxHeight, 300);
  console.log("config BOM regression passed");
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
