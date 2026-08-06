#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync, copyFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const args = new Set(process.argv.slice(2));
const mode = args.has('--full') ? 'full' : args.has('--visual') ? 'visual' : 'quick';
const shouldBuild = args.has('--build') || args.has('--full');
const shouldVisual = args.has('--visual') || args.has('--full');
const shouldInstall = args.has('--install');
const shouldOpen = args.has('--open');
const now = new Date();
const stamp = now.toISOString().replace(/[:.]/g, '-');
const outDir = path.join(ROOT, 'diagnostics', stamp);
const logsDir = path.join(outDir, 'logs');
const responsesDir = path.join(outDir, 'api');
const visualDir = path.join(outDir, 'visual');

mkdirSync(logsDir, { recursive: true });
mkdirSync(responsesDir, { recursive: true });
mkdirSync(visualDir, { recursive: true });

const manifest = {
  generatedAt: now.toISOString(),
  mode,
  repoRoot: ROOT,
  outDir,
  steps: [],
  probes: [],
  assertions: []
};

function redact(text) {
  return String(text || '')
    .replace(/(OPENAI_API_KEY|ANTHROPIC_API_KEY|OPENROUTER_API_KEY|AUTH_TOKEN_SECRET|KEY_ENCRYPTION_SECRET)=\S+/g, '$1=[REDACTED]')
    .replace(/Bearer\s+[A-Za-z0-9._~+/-]+=*/g, 'Bearer [REDACTED]')
    .replace(/"apiKey"\s*:\s*"[^"]+"/g, '"apiKey":"[REDACTED]"')
    .replace(/"token"\s*:\s*"[^"]+"/g, '"token":"[REDACTED]"')
    .replace(/"password"\s*:\s*"[^"]+"/g, '"password":"[REDACTED]"');
}

function safeName(name) {
  return name.replace(/[^a-z0-9_.-]+/gi, '-').replace(/^-|-$/g, '').toLowerCase();
}

function runStep(name, command, commandArgs = [], options = {}) {
  const started = Date.now();
  const file = path.join(logsDir, `${safeName(name)}.log`);
  const result = spawnSync(command, commandArgs, {
    cwd: options.cwd || ROOT,
    encoding: 'utf8',
    timeout: options.timeoutMs || 30_000,
    env: { ...process.env, ...(options.env || {}) }
  });
  const durationMs = Date.now() - started;
  const output = [
    `$ ${[command, ...commandArgs].join(' ')}`,
    `cwd: ${options.cwd || ROOT}`,
    `exitCode: ${result.status ?? 'null'}`,
    `signal: ${result.signal ?? 'none'}`,
    `durationMs: ${durationMs}`,
    '',
    '--- stdout ---',
    redact(result.stdout || ''),
    '',
    '--- stderr ---',
    redact(result.stderr || ''),
    '',
    result.error ? `--- error ---\n${redact(result.error.stack || result.error.message)}` : ''
  ].join('\n');
  writeFileSync(file, output);
  const step = {
    name,
    command: [command, ...commandArgs],
    exitCode: result.status,
    signal: result.signal,
    durationMs,
    log: path.relative(outDir, file),
    ok: result.status === 0
  };
  manifest.steps.push(step);
  return { ...step, stdout: result.stdout || '', stderr: result.stderr || '' };
}

function assert(name, ok, details = '') {
  manifest.assertions.push({ name, ok: !!ok, details });
}

function readJsonIfExists(file) {
  if (!existsSync(file)) return null;
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function copyTailIfExists(source, label, maxBytes = 250_000) {
  if (!existsSync(source)) {
    manifest.steps.push({ name: `copy ${label}`, ok: false, log: null, details: `${source} missing` });
    return null;
  }
  const dest = path.join(logsDir, `${safeName(label)}.log`);
  const stat = statSync(source);
  const start = Math.max(0, stat.size - maxBytes);
  const data = readFileSync(source).subarray(start);
  writeFileSync(dest, redact(data.toString('utf8')));
  manifest.steps.push({
    name: `copy ${label}`,
    ok: true,
    bytes: data.length,
    source,
    log: path.relative(outDir, dest)
  });
  return dest;
}

function listFiles(dir, max = 80) {
  if (!existsSync(dir)) return [];
  try {
    return readdirSync(dir)
      .slice(0, max)
      .map(name => {
        const file = path.join(dir, name);
        const stat = statSync(file);
        return { name, size: stat.size, modifiedAt: stat.mtime.toISOString() };
      });
  } catch {
    return [];
  }
}

async function probe(url, label) {
  const started = Date.now();
  const file = path.join(responsesDir, `${safeName(label)}.json`);
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    const text = await response.text();
    const contentType = response.headers.get('content-type') || '';
    const body = contentType.includes('application/json') ? JSON.stringify(JSON.parse(text), null, 2) : text;
    writeFileSync(file, redact(body));
    const entry = {
      label,
      url,
      ok: response.ok,
      status: response.status,
      durationMs: Date.now() - started,
      file: path.relative(outDir, file)
    };
    manifest.probes.push(entry);
    return entry;
  } catch (error) {
    writeFileSync(file, redact(error.stack || error.message || String(error)));
    const entry = {
      label,
      url,
      ok: false,
      status: null,
      durationMs: Date.now() - started,
      error: error.message || String(error),
      file: path.relative(outDir, file)
    };
    manifest.probes.push(entry);
    return entry;
  }
}

function runtimeUrls() {
  const runtimePath = '/tmp/ai-news-mac-widget-runtime.json';
  const runtime = readJsonIfExists(runtimePath);
  const urls = new Set(['http://127.0.0.1:3000']);
  if (runtime) {
    for (const key of ['url', 'baseUrl', 'apiBaseUrl', 'backendUrl']) {
      if (typeof runtime[key] === 'string' && runtime[key].startsWith('http')) urls.add(runtime[key].replace(/\/$/, ''));
    }
    for (const key of ['port', 'apiPort']) {
      const port = Number(runtime[key]);
      if (Number.isFinite(port)) urls.add(`http://127.0.0.1:${port}`);
    }
  }
  return { runtimePath, runtime, urls: [...urls] };
}

function writeEnvironmentSnapshot() {
  const envPath = path.join(outDir, 'environment.json');
  const runtime = runtimeUrls();
  const runtimePid = Number(runtime.runtime?.pid);
  const runtimeProcessAlive = Number.isFinite(runtimePid) ? (() => {
    try {
      process.kill(runtimePid, 0);
      return true;
    } catch {
      return false;
    }
  })() : null;
  const snapshot = {
    generatedAt: now.toISOString(),
    cwd: ROOT,
    home: homedir(),
    runtime,
    runtimeProcessAlive,
    installedAppCandidates: [
      '/Applications/AI News Widget.app',
      path.join(homedir(), 'Applications/AI News Widget.app')
    ].map(appPath => ({ path: appPath, exists: existsSync(appPath) })),
    logFiles: {
      backend: path.join(homedir(), 'Library/Logs/AINewsMacWidget/backend.log'),
      widget: '/tmp/ai-news-widget-debug.log'
    },
    appSupportFiles: listFiles(path.join(homedir(), 'Library/Application Support/AINewsMacWidget'))
  };
  writeFileSync(envPath, JSON.stringify(snapshot, null, 2));
  manifest.environment = path.relative(outDir, envPath);
  assert('runtime file exists', existsSync(runtime.runtimePath), runtime.runtimePath);
  assert(
    'runtime backend pid alive',
    runtimeProcessAlive !== false,
    runtimePid ? `pid ${runtimePid}` : 'No runtime pid in runtime file'
  );
  assert('installed app exists', snapshot.installedAppCandidates.some(entry => entry.exists), 'Checked /Applications and ~/Applications');
  return snapshot;
}

async function main() {
  const envSnapshot = writeEnvironmentSnapshot();

  runStep('git status', 'git', ['status', '--short']);
  runStep('git recent commits', 'git', ['log', '--oneline', '--decorate', '-12']);
  runStep('node version', 'node', ['--version']);
  runStep('npm version', 'npm', ['--version']);
  runStep('package scripts', 'node', ['-e', "const p=require('./package.json'); console.log(JSON.stringify(p.scripts,null,2))"]);
  runStep('widget doctor', 'bash', ['scripts/widget-doctor.sh']);

  if (shouldBuild) {
    runStep('build backend', 'npm', ['run', 'build:backend'], { timeoutMs: 120_000 });
    runStep('build native', 'npm', ['run', 'build:native'], { timeoutMs: 120_000 });
  }
  if (shouldInstall) {
    runStep('install app', 'npm', ['run', 'install:app'], { timeoutMs: 240_000 });
  }
  if (shouldOpen) {
    runStep('open app', 'npm', ['run', 'open:app'], { timeoutMs: 30_000 });
  }

  copyTailIfExists(envSnapshot.logFiles.backend, 'backend-log-tail');
  copyTailIfExists(envSnapshot.logFiles.widget, 'widget-debug-log-tail');
  copyTailIfExists('/tmp/ai-news-mac-widget-runtime.json', 'runtime-json', 32_000);

  for (const baseUrl of runtimeUrls().urls) {
    await probe(`${baseUrl}/api/health`, `${baseUrl} api health`);
    await probe(`${baseUrl}/health`, `${baseUrl} root health`);
    await probe(`${baseUrl}/api/ops/ai-jobs?limit=120&deadLimit=80`, `${baseUrl} ai jobs`);
    await probe(`${baseUrl}/api/ops/ai-summary-debug?limit=80`, `${baseUrl} summary debug`);
    await probe(`${baseUrl}/api/runtime/config`, `${baseUrl} runtime config`);
  }

  const healthProbe = manifest.probes.find(entry => entry.label.includes('api health') && entry.ok);
  assert('backend api health ok', !!healthProbe, healthProbe ? healthProbe.url : 'No healthy /api/health response');
  assert('backend log copied', manifest.steps.some(step => step.name === 'copy backend-log-tail' && step.ok), envSnapshot.logFiles.backend);
  assert('widget debug log copied', manifest.steps.some(step => step.name === 'copy widget-debug-log-tail' && step.ok), envSnapshot.logFiles.widget);

  if (shouldVisual) {
    const screenshotPath = path.join(visualDir, 'desktop.png');
    runStep('visual desktop screenshot', 'screencapture', ['-x', screenshotPath], { timeoutMs: 20_000 });
    assert('desktop screenshot captured', existsSync(screenshotPath) && statSync(screenshotPath).size > 10_000, screenshotPath);

    const appleScript = [
      'tell application "System Events"',
      'set output to ""',
      'repeat with proc in (processes whose name contains "AINews" or name contains "AI News")',
      'set output to output & "process=" & (name of proc) & linefeed',
      'repeat with win in windows of proc',
      'set output to output & "window=" & (name of win) & " position=" & ((position of win) as text) & " size=" & ((size of win) as text) & linefeed',
      'end repeat',
      'end repeat',
      'return output',
      'end tell'
    ].join('\n');
    const windows = runStep('visual window bounds', 'osascript', ['-e', appleScript], { timeoutMs: 20_000 });
    writeFileSync(path.join(visualDir, 'window-bounds.txt'), redact(windows.stdout || windows.stderr || ''));
    assert('app window bounds captured', /window=/.test(windows.stdout || ''), 'Requires Accessibility permission for Terminal/Codex if false.');
  }

  const reportPath = path.join(outDir, 'REPORT.md');
  const failingAssertions = manifest.assertions.filter(entry => !entry.ok);
  const report = [
    '# AI News Mac Widget Diagnostic Report',
    '',
    `Generated: ${manifest.generatedAt}`,
    `Mode: ${mode}`,
    `Repo: ${ROOT}`,
    '',
    '## Quick Verdict',
    '',
    failingAssertions.length
      ? `Attention needed: ${failingAssertions.length} assertion(s) failed.`
      : 'Core diagnostics passed.',
    '',
    '## Assertions',
    '',
    ...manifest.assertions.map(entry => `- ${entry.ok ? 'PASS' : 'FAIL'} - ${entry.name}${entry.details ? `: ${entry.details}` : ''}`),
    '',
    '## API Probes',
    '',
    ...manifest.probes.map(entry => `- ${entry.ok ? 'PASS' : 'FAIL'} - ${entry.label} - ${entry.status ?? 'no status'} - ${entry.durationMs}ms - ${entry.file}`),
    '',
    '## Command Logs',
    '',
    ...manifest.steps.map(step => `- ${step.ok ? 'PASS' : 'FAIL'} - ${step.name}${step.log ? ` - ${step.log}` : ''}`),
    '',
    '## First Files To Inspect',
    '',
    '- `api/*ai-jobs*.json` for queue size, stalled jobs, skips, drops, and dead letters.',
    '- `api/*summary-debug*.json` for summary generation timing and failures.',
    '- `logs/backend-log-tail.log` for backend crashes, fetch errors, and API errors.',
    '- `logs/widget-debug-log-tail.log` for floating widget resize/mode/snapshot behavior.',
    '- `visual/desktop.png` and `visual/window-bounds.txt` when `--visual` was used.',
    '',
    '## Reproduce Commands',
    '',
    '```bash',
    'npm run diagnose:quick',
    'npm run diagnose:visual',
    'npm run diagnose:full',
    '```',
    ''
  ].join('\n');
  writeFileSync(reportPath, report);

  writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`Diagnostic pack written to ${outDir}`);
  console.log(`Report: ${reportPath}`);
  if (failingAssertions.length) {
    console.log(`Attention: ${failingAssertions.length} assertion(s) failed. Open REPORT.md first.`);
  }
}

main().catch(error => {
  const crashPath = path.join(outDir, 'diagnose-crash.log');
  writeFileSync(crashPath, redact(error.stack || error.message || String(error)));
  console.error(`diagnose failed: ${error.message || error}`);
  console.error(`Crash log: ${crashPath}`);
  process.exitCode = 1;
});
