const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_APP_LOG_RELATIVE_PATH = "logs/codex-limit-watcher.log";
const MAX_APP_LOG_BYTES = 2 * 1024 * 1024;
const ROTATED_APP_LOG_COPIES = 4;

function appendAppLog(config, rootDir, entry) {
  const logPath = resolveAppLogPath(config, rootDir);
  ensureAppLogDir(config, rootDir);
  rotateDefaultAppLogIfNeeded(logPath, rootDir);
  fs.appendFileSync(logPath, `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`);
}

function ensureAppLogDir(config, rootDir) {
  fs.mkdirSync(path.dirname(resolveAppLogPath(config, rootDir)), { recursive: true });
}

function resolveAppLogPath(config, rootDir) {
  return path.resolve(rootDir, (config && config.logPath) || DEFAULT_APP_LOG_RELATIVE_PATH);
}

function rotateDefaultAppLogIfNeeded(logPath, rootDir) {
  if (!isDefaultAppLogPath(logPath, rootDir)) {
    return false;
  }

  try {
    return rotateLogIfNeeded(logPath, MAX_APP_LOG_BYTES, ROTATED_APP_LOG_COPIES);
  } catch {
    return false;
  }
}

function isDefaultAppLogPath(logPath, rootDir) {
  return path.resolve(logPath) === path.resolve(rootDir, DEFAULT_APP_LOG_RELATIVE_PATH);
}

function rotateLogIfNeeded(logPath, maxBytes, rotatedCopies) {
  let stats;
  try {
    stats = fs.statSync(logPath);
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return false;
    }
    throw error;
  }

  if (!stats.isFile() || stats.size < maxBytes) {
    return false;
  }

  for (let index = rotatedCopies; index >= 1; index -= 1) {
    const source = index === 1 ? logPath : `${logPath}.${index - 1}`;
    const target = `${logPath}.${index}`;

    removeFileIfExists(target);
    if (fs.existsSync(source)) {
      fs.renameSync(source, target);
    }
  }

  return true;
}

function removeFileIfExists(filePath) {
  try {
    fs.unlinkSync(filePath);
  } catch (error) {
    if (!error || error.code !== "ENOENT") {
      throw error;
    }
  }
}

module.exports = {
  appendAppLog,
  ensureAppLogDir,
  MAX_APP_LOG_BYTES,
  ROTATED_APP_LOG_COPIES,
};
