const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { AppServerClient } = require("./appServerClient");
const { appendAppLog, ensureAppLogDir } = require("./logging");

const rootDir = path.resolve(__dirname, "..");
const CLEANUP_GRACE_MS = 2000;
const CLEANUP_FORCE_MS = 2000;
const DESCENDANT_QUERY_TIMEOUT_MS = 5000;

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

async function main() {
  const { config, configPath } = loadConfig();
  ensureAppLogDir(config, rootDir);

  const client = new AppServerClient({ codexCommand: config.codexCommand });
  const result = {
    mode: "diagnose-app-server",
    configPath,
    initializeSucceeded: false,
    processAliveAfterInitialize: false,
    cleanedUpChild: false,
    diagnostics: null,
    initialize: null,
    error: null,
    cleanup: null,
  };

  try {
    const init = await client.start();
    result.initializeSucceeded = true;
    result.initialize = {
      platformOs: init && init.platformOs ? init.platformOs : null,
      userAgent: init && init.userAgent ? init.userAgent : null,
    };
    await delay(1500);
    result.processAliveAfterInitialize = isProcessStillOpen(client.child);
  } catch (error) {
    result.error = error.message;
    result.diagnostics = error.appServerDiagnostics || client.getDiagnostics();
  } finally {
    if (!result.diagnostics) {
      result.diagnostics = client.getDiagnostics();
    }

    result.cleanup = await cleanupClient(client);
    result.cleanedUpChild = result.cleanup.cleanedUp;
    log(config, {
      source: "codex-app-server",
      mode: result.mode,
      appServerDiagnostic: result,
    });
    console.log(JSON.stringify(result, null, 2));
    closeClientHandles(client);
  }

  if (!result.initializeSucceeded || !result.cleanedUpChild) {
    process.exitCode = 1;
  }
}

function loadConfig() {
  const file = path.join(rootDir, "config.json");
  const fallback = path.join(rootDir, "config.example.json");
  const selected = fs.existsSync(file) ? file : fallback;
  return {
    config: JSON.parse(fs.readFileSync(selected, "utf8")),
    configPath: selected,
  };
}

function log(config, entry) {
  appendAppLog(config, rootDir, entry);
}

async function cleanupClient(client) {
  const child = client.child;
  if (!child) {
    return {
      attempted: false,
      cleanedUp: true,
      childPid: null,
      exitObserved: false,
      exitCode: null,
      signalCode: null,
      descendantCheckPerformed: false,
      descendantStillRunning: null,
      warning: null,
    };
  }

  const cleanup = {
    attempted: true,
    childPid: child.pid || null,
    cleanedUp: false,
    exitObserved: false,
    exitCode: child.exitCode,
    signalCode: child.signalCode,
    descendantCheckPerformed: false,
    descendantStillRunning: null,
    warning: null,
  };

  const exitState = await stopAndWaitForExit(client, child);
  cleanup.exitObserved = exitState.exitObserved;
  cleanup.exitCode = exitState.exitCode;
  cleanup.signalCode = exitState.signalCode;

  if (!cleanup.exitObserved) {
    cleanup.warning = "Cleanup timed out before the direct app-server child reported an exit event.";
    return cleanup;
  }

  const descendantCheck = inspectWindowsDescendants(cleanup.childPid);
  cleanup.descendantCheckPerformed = descendantCheck.performed;
  cleanup.descendantStillRunning = descendantCheck.descendantStillRunning;

  if (!descendantCheck.performed) {
    cleanup.warning = descendantCheck.warning || "Cleanup is uncertain because descendant verification could not be completed.";
    return cleanup;
  }

  if (descendantCheck.descendantStillRunning === true) {
    cleanup.warning = descendantCheck.warning || "Cleanup failed because a Codex app-server descendant still appears to be running.";
    return cleanup;
  }

  if (descendantCheck.descendantStillRunning == null) {
    cleanup.warning = descendantCheck.warning || "Cleanup is uncertain because descendant status could not be determined.";
    return cleanup;
  }

  cleanup.cleanedUp = true;
  return cleanup;
}

async function stopAndWaitForExit(client, child) {
  if (!child) {
    return { exitObserved: false, exitCode: null, signalCode: null };
  }

  if (hasObservedExit(child)) {
    return {
      exitObserved: true,
      exitCode: child.exitCode,
      signalCode: child.signalCode,
    };
  }

  let exitWait = waitForExit(child, CLEANUP_GRACE_MS);
  client.stop();
  let exitState = await exitWait;

  if (exitState.exitObserved) {
    return exitState;
  }

  try {
    child.kill("SIGKILL");
  } catch {
    // If the process exited between checks, the second wait will observe that.
  }

  exitWait = waitForExit(child, CLEANUP_FORCE_MS);
  exitState = await exitWait;
  if (exitState.exitObserved) {
    return exitState;
  }

  return {
    exitObserved: hasObservedExit(child),
    exitCode: child.exitCode,
    signalCode: child.signalCode,
  };
}

function waitForExit(child, timeoutMs) {
  if (!child) {
    return Promise.resolve({ exitObserved: false, exitCode: null, signalCode: null });
  }

  if (hasObservedExit(child)) {
    return Promise.resolve({
      exitObserved: true,
      exitCode: child.exitCode,
      signalCode: child.signalCode,
    });
  }

  return new Promise((resolve) => {
    let settled = false;
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      child.removeListener("exit", onExit);
      resolve(payload);
    };
    const onExit = (code, signal) => finish({ exitObserved: true, exitCode: code, signalCode: signal });
    const timeout = setTimeout(() => {
      finish({
        exitObserved: hasObservedExit(child),
        exitCode: child.exitCode,
        signalCode: child.signalCode,
      });
    }, timeoutMs);

    child.once("exit", onExit);
  });
}

function inspectWindowsDescendants(rootPid) {
  if (!rootPid || process.platform !== "win32") {
    return {
      performed: false,
      descendantStillRunning: null,
      warning: rootPid
        ? "Cleanup is uncertain because descendant verification is only implemented for Windows."
        : "Cleanup is uncertain because the direct child PID was unavailable for descendant verification.",
    };
  }

  const result = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-Command", buildDescendantQueryScript(rootPid)],
    {
      encoding: "utf8",
      timeout: DESCENDANT_QUERY_TIMEOUT_MS,
      windowsHide: true,
    },
  );

  if (result.error) {
    return {
      performed: false,
      descendantStillRunning: null,
      warning: `Cleanup is uncertain because descendant verification failed: ${sanitizeProcessMessage(result.error.message)}`,
    };
  }

  if (result.status !== 0) {
    const stderr = sanitizeProcessMessage(result.stderr || "");
    const detail = stderr || `PowerShell exited with code ${result.status}`;
    return {
      performed: false,
      descendantStillRunning: null,
      warning: `Cleanup is uncertain because descendant verification failed: ${detail}`,
    };
  }

  let parsed;
  try {
    parsed = JSON.parse(result.stdout || "{}");
  } catch {
    return {
      performed: false,
      descendantStillRunning: null,
      warning: "Cleanup is uncertain because descendant verification returned unreadable output.",
    };
  }

  const descendants = Array.isArray(parsed.descendants) ? parsed.descendants : [];
  const matchingDescendantCount = Number(parsed.matchingDescendantCount || 0);
  const descendantCount = Number(parsed.descendantCount || descendants.length || 0);

  if (!Number.isFinite(descendantCount) || !Number.isFinite(matchingDescendantCount)) {
    return {
      performed: false,
      descendantStillRunning: null,
      warning: "Cleanup is uncertain because descendant verification returned invalid counts.",
    };
  }

  if (descendantCount === 0) {
    return {
      performed: true,
      descendantStillRunning: false,
      warning: null,
    };
  }

  if (matchingDescendantCount === 0) {
    return {
      performed: true,
      descendantStillRunning: null,
      warning: `Cleanup is uncertain because non-matching descendants still exist after cleanup (descendants=${descendantCount}, matching=0).`,
    };
  }

  return {
    performed: true,
    descendantStillRunning: true,
    warning: `Codex-related descendant processes still appear to be running after cleanup (descendants=${descendantCount}, matching=${matchingDescendantCount}).`,
  };
}

function buildDescendantQueryScript(rootPid) {
  return [
    "$ErrorActionPreference = 'Stop'",
    `$RootPid = ${Number(rootPid)}`,
    "$procs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, Name, CommandLine",
    "$byParent = @{}",
    "foreach ($proc in $procs) {",
    "  $key = [string]$proc.ParentProcessId",
    "  if (-not $byParent.ContainsKey($key)) { $byParent[$key] = New-Object System.Collections.ArrayList }",
    "  [void]$byParent[$key].Add($proc)",
    "}",
    "$queue = New-Object System.Collections.ArrayList",
    "$visited = New-Object 'System.Collections.Generic.HashSet[int]'",
    "$descendants = New-Object System.Collections.ArrayList",
    "$rootKey = [string]$RootPid",
    "if ($byParent.ContainsKey($rootKey)) { foreach ($proc in $byParent[$rootKey]) { [void]$queue.Add($proc) } }",
    "while ($queue.Count -gt 0) {",
    "  $proc = $queue[0]",
    "  if ($queue.Count -gt 1) { $queue.RemoveRange(0, 1) } else { $queue.Clear() }",
    "  $procId = [int]$proc.ProcessId",
    "  if (-not $visited.Add($procId)) { continue }",
    "  $commandLine = [string]$proc.CommandLine",
    "  $lower = $commandLine.ToLowerInvariant()",
    "  $name = [string]$proc.Name",
    "  $matches = $name -match 'codex|node|cmd|powershell' -or $lower.Contains('codex') -or $lower.Contains('app-server') -or $lower.Contains('stdio://')",
    "  [void]$descendants.Add([pscustomobject]@{ processId = $procId; parentProcessId = [int]$proc.ParentProcessId; name = $name; matchesCodexOrAppServer = [bool]$matches })",
    "  $childKey = [string]$procId",
    "  if ($byParent.ContainsKey($childKey)) { foreach ($child in $byParent[$childKey]) { [void]$queue.Add($child) } }",
    "}",
    "$result = [ordered]@{",
    "  rootPid = $RootPid",
    "  descendantCount = $descendants.Count",
    "  matchingDescendantCount = @($descendants | Where-Object { $_.matchesCodexOrAppServer }).Count",
    "  descendants = @($descendants | Select-Object -First 12)",
    "}",
    "$result | ConvertTo-Json -Compress -Depth 4",
  ].join("\n");
}

function hasObservedExit(child) {
  return Boolean(child && (child.exitCode !== null || child.signalCode !== null));
}

function isProcessStillOpen(child) {
  return Boolean(child && child.exitCode === null && child.signalCode === null);
}

function sanitizeProcessMessage(message) {
  return String(message || "").replace(/\s+/g, " ").trim().slice(0, 300);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function closeClientHandles(client) {
  try {
    if (client.rl) client.rl.close();
  } catch {
  }

  const child = client.child;
  if (!child) {
    return;
  }

  for (const stream of [child.stdin, child.stdout, child.stderr]) {
    try {
      if (stream && !stream.destroyed) stream.destroy();
    } catch {
    }
  }
}
