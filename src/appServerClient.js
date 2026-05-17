const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");

class AppServerClient {
  constructor(options = {}) {
    this.codexCommand = options.codexCommand || findCodexCommand();
    this.nextId = 1;
    this.pending = new Map();
    this.notifications = [];
    this.stderr = [];
    this.child = null;
    this.rl = null;
  }

  async start() {
    if (!this.codexCommand) {
      throw new Error("Could not find codex command. Set config.codexCommand to codex.ps1, codex.cmd, or codex.exe.");
    }

    const spawnSpec = buildSpawnSpec(this.codexCommand, ["app-server", "--listen", "stdio://"]);
    this.child = spawn(spawnSpec.command, spawnSpec.args, {
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
      shell: spawnSpec.shell || false,
    });

    this.child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      const lines = text.split(/\r?\n/).filter(Boolean);
      for (const line of lines) this.stderr.push(redactLogLine(line));
      if (this.stderr.length > 20) this.stderr.splice(0, this.stderr.length - 20);
    });

    this.rl = readline.createInterface({ input: this.child.stdout });
    this.rl.on("line", (line) => this.#handleLine(line));
    this.child.on("exit", (code, signal) => {
      const err = new Error(`codex app-server exited with code=${code} signal=${signal}`);
      for (const item of this.pending.values()) item.reject(err);
      this.pending.clear();
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
    const id = this.nextId++;
    const payload = params === undefined ? { id, method } : { id, method, params };
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timed out waiting for ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timeout });
      this.child.stdin.write(`${JSON.stringify(payload)}\n`);
    });
  }

  stop() {
    if (this.rl) this.rl.close();
    if (this.child && !this.child.killed) this.child.kill();
  }

  #handleLine(line) {
    if (!line.trim()) return;
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
      if (msg.error) item.reject(new Error(`${msg.error.code || "error"} ${msg.error.message}`));
      else item.resolve(msg.result);
      return;
    }

    if (msg.method) this.notifications.push(msg);
  }
}

function findCodexCommand() {
  const candidates = [
    path.join(os.homedir(), "AppData", "Roaming", "npm", "codex.cmd"),
    path.join(os.homedir(), "AppData", "Roaming", "npm", "codex.ps1"),
    "C:\\Program Files\\WindowsApps\\OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0\\app\\resources\\codex.exe",
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || "codex";
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
  return line
    .replace(/([?&](?:token|key|secret|cookie|auth|cf_chl_[^=]+)=)[^&\s"']+/gi, "$1[REDACTED]")
    .replace(/("(?:token|secret|cookie|auth|key|email|account)[^"]*"\s*:\s*)"[^"]*"/gi, "$1\"[REDACTED]\"");
}

module.exports = { AppServerClient, redactLogLine };
