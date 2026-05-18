const fs = require("node:fs");
const path = require("node:path");

function loadConfig(rootDir) {
  const file = path.join(rootDir, "config.json");
  const fallback = path.join(rootDir, "config.example.json");
  const selected = fs.existsSync(file) ? file : fallback;
  return {
    config: readJsonFile(selected),
    configPath: selected,
  };
}

function readJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(raw);
}

module.exports = { loadConfig, readJsonFile };
