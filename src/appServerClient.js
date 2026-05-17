const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");

const RECENT_LINE_LIMIT = 20;

class AppServerClient {
  constructor(options = {}) {
    const commandInfo = findCodexCommand(options.codexCommand);
    this.codexCommand = commandInfo.command;
    this.checkedCodexCandidates = commandInfo.checkedCandidates;
    this.nextId = 1;
    this.pending = new Map();
    this.notifications = [];
    this.stdout = [];
    this.stderr = [];
    this.child = null;
    this.rl = null;
    this.cwd = process.cwd();
    this.spawnSpec = null;
    this.lastExit = null;
    this.childError = null;
  }

  async start() {
    if (!this.codexCommand) {
      throw attachDiagnostics(
        new Error("Could not find codex command. Set config.codexCommand to codex.ps1, codex.cmd, or codex.exe."),
        this.getDiagnostics(),
      );
    }

    const spawnSpec = buildSpawnSpec(this.codexCommand, ["app-server", "--listen", "stdio://"]);
    this.spawnSpec = spawnSpec;
    this.child = spawn(spawnSpec.command, spawnSpec.args, {
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
      shell: spawnSpec.shell || false,
    });

    this.child.on("error", (error) => {
      const message = redactLogLine(error && error.message ? error.message : String(error));
      this.childError = { message, name: error && error.name ? error.name : "Error" };
      this.#rejectPending(attachDiagnostics(new Error(`codex app-server failed to start: ${message}`), this.getDiagnostics()));
    });

    this.child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      const lines = text.split(/\r?\n/).filter(Boolean);
      for (const line of lines) pushRecentLine(this.stderr, redactLogLine(line));
    });

    this.rl = readline.createInterface({ input: this.child.stdout });
    this.rl.on("line", (line) => this.#handleLine(line));
    this.child.on("exit", (code, signal) => {
      this.lastExit = { code, signal };
      this.#rejectPending(
        attachDiagnostics(new Error(`codex app-server exited with code=${code} signal=${signal}`), this.getDiagnostics()),
      );
    });

    return this.request("initialize", {
      clientInfo: { name: "codex-limit-watcher", title: "Codex Limit Watcher", version: "0.1.0" },
      capabilities: { experimentalApi: true },
    }, 15000);
  }

  readRateLimits() {
    return this.request("account/rateLimits/read", undefined, 30000);
  }

  request(method, params, timeoutMs = 30000) {
    if (!this.child || !this.child.stdin) {
      return Promise.reject(attachDiagnostics(new Error(`codex app-server is not running for ${method}`), this.getDiagnostics()));
    }

    const id = this.nextId++;
    const payload = params === undefined ? { id, method } : { id, method, params };
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(attachDiagnostics(new Error(`Timed out waiting for ${method}`), this.getDiagnostics()));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timeout });

      try {
        this.child.stdin.write(`${JSON.stringify(payload)}\n`);
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        const message = redactLogLine(error && error.message ? error.message : String(error));
        reject(attachDiagnostics(new Error(`Failed to send ${method}: ${message}`), this.getDiagnostics()));
      }
    });
  }

  stop() {
    if (this.rl) this.rl.close();
    if (this.child && !this.child.killed) this.child.kill();
  }

  getDiagnostics() {
    const pathValue = process.env.PATH || process.env.Path || "";
    return {
      resolvedCodexCommand: this.codexCommand,
      checkedCodexCandidates: this.checkedCodexCandidates,
      spawnCommand: this.spawnSpec ? this.spawnSpec.command : null,
      spawnArgs: this.spawnSpec ? this.spawnSpec.args : [],
      spawnShell: this.spawnSpec ? Boolean(this.spawnSpec.shell) : false,
      cwd: this.cwd,
      env: {
        pathPresent: Boolean(pathValue),
        pathLength: pathValue.length,
        userProfile: process.env.USERPROFILE || null,
        home: process.env.HOME || null,
        platform: process.platform,
        nodeVersion: process.version,
      },
      recentStdout: [...this.stdout],
      recentStderr: [...this.stderr],
      childPid: this.child && this.child.pid ? this.child.pid : null,
      childError: this.childError,
      lastExit: this.lastExit,
    };
  }

  #handleLine(line) {
    if (!line.trim()) return;
    pushRecentLine(this.stdout, redactLogLine(line));
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      this.notifications.push({ method: "non-json", params: redactLogLine(line) });
      return;
    }

    if (Object.prototype.hasOwnProperty.call(msg, "id")) {
      const item = this.pending.get(msg.id);
      if (!item) return;
      clearTimeout(item.timeout);
      this.pending.delete(msg.id);
      if (msg.error) {
        item.reject(
          attachDiagnostics(
            new Error(`${msg.error.code || "error"} ${redactLogLine(msg.error.message || "Unknown app-server error")}`),
            this.getDiagnostics(),
          ),
        );
      }
      else item.resolve(msg.result);
      return;
    }

    if (msg.method) this.notifications.push(msg);
  }

  #rejectPending(error) {
    for (const item of this.pending.values()) {
      clearTimeout(item.timeout);
      item.reject(error);
    }
    this.pending.clear();
  }
}

function findCodexCommand(configuredCommand) {
  if (configuredCommand) {
    return {
      command: configuredCommand,
      checkedCandidates: [describeCandidate(configuredCommand, "config.codexCommand")],
    };
  }

  const candidates = [
    path.join(os.homedir(), "AppData", "Roaming", "npm", "codex.cmd"),
    path.join(os.homedir(), "AppData", "Roaming", "npm", "codex.ps1"),
    "C:\\Program Files\\WindowsApps\\OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0\\app\\resources\\codex.exe",
  ];
  const checkedCandidates = candidates.map((candidate) => describeCandidate(candidate, "default"));
  const resolved = checkedCandidates.find((candidate) => candidate.exists)?.candidate || "codex";
  checkedCandidates.push(describeCandidate("codex", "fallback"));
  return { command: resolved, checkedCandidates };
}

function buildSpawnSpec(command, args = []) {
  if (/\.ps1$/i.test(command)) {
    return {
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", command, ...args],
    };
  }
  if (/\.cmd$/i.test(command)) {
    return { command, args, shell: true };
  }
  return { command, args };
}

function redactLogLine(line) {
  return truncateDiagnosticLine(line
    .replace(/([?&](?:token|api(?:[_-]?key)?|key|secret|cookie|auth(?:orization)?|bearer|session|cf_chl_[^=]+)=)[^&\s"']+/gi, "$1[REDACTED]")
    .replace(/("(?:token|secret|cookie|auth(?:orization)?|bearer|api(?:[_-]?key)?|key|session|email|account)[^"]*"\s*:\s*)"[^"]*"/gi, "$1\"[REDACTED]\"")
    .replace(/\b(authorization|bearer|token|api(?:[_-]?key)?|session|cookie)\b(\s*[:=]\s*)([^\s,;]+)/gi, "$1$2[REDACTED]")
    .replace(/\bBearer\s+[A-Za-z0-9\-._~+/]+=*/gi, "Bearer [REDACTED]")
    .replace(/(<html>|<!DOCTYPE html)[\s\S]*/i, "$1 [HTML response omitted]"));
}

function attachDiagnostics(error, diagnostics) {
  error.appServerDiagnostics = diagnostics;
  return error;
}

function describeCandidate(candidate, source) {
  const exists = looksLikeFilePath(candidate) ? fs.existsSync(candidate) : null;
  return { candidate, source, exists };
}

function looksLikeFilePath(candidate) {
  return /[\\/]/.test(candidate) || /\.(?:cmd|ps1|exe)$/i.test(candidate);
}

function pushRecentLine(target, line) {
  target.push(line);
  if (target.length > RECENT_LINE_LIMIT) {
    target.splice(0, target.length - RECENT_LINE_LIMIT);
  }
}

function truncateDiagnosticLine(line) {
  const maxLength = 600;
  if (line.length <= maxLength) {
    return line;
  }
  return `${line.slice(0, maxLength)}... [truncated ${line.length - maxLength} chars]`;
}

module.exports = { AppServerClient, redactLogLine };
