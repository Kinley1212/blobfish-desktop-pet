const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn, execFileSync } = require('node:child_process');
let binary;
let buildDirectory;
const fixture = path.resolve(__dirname, 'fixtures/codex-observer-server.cjs');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
test.before(() => {
  if (process.platform !== 'darwin') return;
  buildDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-observer-build-'));
  binary = path.join(buildDirectory, 'blobfish-codex-observer');
  execFileSync('/bin/sh', [path.resolve(__dirname, '../scripts/build-codex-observer.sh'), binary], { timeout: 90000 });
});
test.after(() => { if (buildDirectory) fs.rmSync(buildDirectory, { recursive: true, force: true }); });

test('transparent observer preserves bytes, projects real requests, expires and respects privacy', { skip: process.platform !== 'darwin', timeout: 25000 }, async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-observer-'));
  fs.chmodSync(root, 0o700);
  const directory = path.join(root, 'observations');
  const settings = path.join(root, 'settings.json');
  const writeSettings = enabled => fs.writeFileSync(settings, JSON.stringify({ integrations: { codex: true, codexQuestions: enabled } }), { mode: 0o600 });
  writeSettings(true);
  const env = { ...process.env, BLOBFISH_CODEX_REAL_CLI: fixture, BLOBFISH_CODEX_OBSERVATION_DIR: directory, BLOBFISH_SETTINGS: settings };
  assert.equal(execFileSync(binary, ['--version'], { env, encoding: 'utf8' }), 'fixture-cli\n');
  const child = spawn(binary, ['app-server'], { env });
  let stderr = '', output = '', collect = true;
  let receivedBytes = 0;
  const receivedHash = crypto.createHash('sha256');
  child.stdout.on('data', chunk => { receivedBytes += chunk.length; receivedHash.update(chunk); if (collect) output += chunk; });
  child.stderr.on('data', chunk => stderr += chunk);
  const closed = new Promise(resolve => child.on('close', resolve));
  const input = [];
  const send = message => { const line = JSON.stringify(message) + '\n'; input.push(line); child.stdin.write(line); };
  const snapshot = () => JSON.parse(fs.readFileSync(path.join(directory, fs.readdirSync(directory).find(name => name.endsWith('.json')))));
  try {
    send({ method: 'turn/started', params: { threadId: 't1', turn: { id: 'turn1' } } });
    send({ method: 'item/autoApprovalReview/started', params: { threadId: 't1', turnId: 'turn1', reviewId: 'r1' } });
    await wait(2400);
    assert.deepEqual(snapshot().threads[0].approvals, []);
    send({ id: 5, method: 'item/commandExecution/requestApproval', params: { threadId: 't1', turnId: 'turn1', command: 'DO NOT STORE THIS' } });
    send({ id: 'q1', method: 'item/tool/requestUserInput', params: { threadId: 't1', turnId: 'turn1', itemId: 'call1', isBlocking: false, questions: [
      { id: 'a', question: 'First?', options: [{ label: 'A', description: 'Option A' }] },
      { id: 'b', question: 'Second?', options: null },
      { id: 'c', question: 'SECRET QUESTION', isSecret: true }
    ] } });
    await wait(2400);
    let s = snapshot();
    assert.deepEqual(s.threads[0].approvals, ['n:5']);
    assert.deepEqual(s.threads[0].blockingQuestions, []);
    assert.equal(s.threads[0].questions[0].questions.length, 2);
    assert.doesNotMatch(JSON.stringify(s), /SECRET|DO NOT STORE/);
    const malformed = 'not-json\n' + 'x'.repeat(1100 * 1024) + '\n';
    input.push(malformed); child.stdin.write(malformed);
    send({ method: 'serverRequest/resolved', params: { threadId: 't1', requestId: 5 } });
    writeSettings(false);
    await wait(2400);
    s = snapshot();
    assert.deepEqual(s.threads[0].approvals, []);
    assert.deepEqual(s.threads[0].questions, []);
    assert.equal(output, input.join(''));
    try {
      const sample = execFileSync('/bin/ps', ['-p', String(child.pid), '-o', '%cpu=,rss='], { encoding: 'utf8' }).trim();
      t.diagnostic(`Observer idle CPU% / RSS KiB: ${sample}`);
      const [cpu, rss] = sample.split(/\s+/).map(Number);
      assert.ok(cpu < 2, `idle CPU too high: ${cpu}%`);
      assert.ok(rss < 40 * 1024, `observer RSS too high: ${rss / 1024} MiB`);
    } catch (error) { if (error.code === 'ERR_ASSERTION') throw error; t.diagnostic('Process accounting unavailable in this sandbox'); }
    collect = false;
    const started = performance.now();
    child.stdin.end('STRESS\n');
    assert.equal(await closed, 0, stderr);
    const expected = crypto.createHash('sha256').update(input.join(''));
    for (let i = 0; i < 10000; i++) expected.update(JSON.stringify({ method: 'item/agentMessage/delta', params: { threadId: 't1', delta: 'x'.repeat(1024) } }) + '\n');
    assert.equal(receivedHash.digest('hex'), expected.digest('hex'));
    t.diagnostic(`10,000 streamed events, ${(receivedBytes / 1024 / 1024).toFixed(2)} MiB, ${(performance.now() - started).toFixed(0)} ms, exact byte match`);
    assert.equal(fs.readdirSync(directory).filter(name => name.endsWith('.json')).length, 0);
  } finally { if (child.exitCode == null) child.kill(); await closed; fs.rmSync(root, { recursive: true, force: true }); }
});

test('desktop output disconnect terminates the owned app-server', { skip: process.platform !== 'darwin', timeout: 8000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-observer-disconnect-'));
  fs.chmodSync(root, 0o700);
  const child = spawn(binary, ['app-server'], { env: {
    ...process.env, BLOBFISH_CODEX_REAL_CLI: fixture,
    BLOBFISH_CODEX_OBSERVATION_DIR: path.join(root, 'observations'), BLOBFISH_SETTINGS: path.join(root, 'absent-settings')
  } });
  child.stderr.resume();
  const closed = new Promise(resolve => child.once('close', resolve));
  let serverPID;
  try {
    const response = new Promise(resolve => child.stdout.once('data', resolve));
    child.stdin.write('PID\n');
    serverPID = JSON.parse(String(await response)).fixturePID;
    child.stdout.destroy();
    child.stdin.write('output-after-disconnect\n');
    await closed;
    await wait(150);
    assert.throws(() => process.kill(serverPID, 0), { code: 'ESRCH' });
  } finally {
    if (child.exitCode == null && child.signalCode == null) child.kill();
    if (serverPID) { try { process.kill(serverPID, 'SIGTERM'); } catch {} }
    await closed;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('100,000 deltas and 8,000 lifecycle events stay byte-exact and memory-bounded', { skip: process.platform !== 'darwin', timeout: 90000 }, async t => {
  const { once } = require('node:events');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-observer-stress-'));
  fs.chmodSync(root, 0o700);
  const directory = path.join(root, 'observations');
  const settings = path.join(root, 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({ integrations: { codex: true, codexQuestions: true } }), { mode: 0o600 });
  const child = spawn(binary, ['app-server'], { env: { ...process.env, BLOBFISH_CODEX_REAL_CLI: fixture, BLOBFISH_CODEX_OBSERVATION_DIR: directory, BLOBFISH_SETTINGS: settings } });
  child.stderr.resume();
  const closed = new Promise(resolve => child.once('close', resolve));
  const actualHash = crypto.createHash('sha256'), expectedHash = crypto.createHash('sha256');
  let received = 0, sent = 0, peakRSS = 0, peakCPU = 0;
  child.stdout.on('data', chunk => { received += chunk.length; actualHash.update(chunk); });
  const sample = () => {
    const [cpu, rss] = execFileSync('/bin/ps', ['-p', String(child.pid), '-o', '%cpu=,rss='], { encoding: 'utf8' }).trim().split(/\s+/).map(Number);
    peakRSS = Math.max(peakRSS, rss); peakCPU = Math.max(peakCPU, cpu);
    return { cpu, rss };
  };
  const sampling = setInterval(sample, 1000);
  const send = async message => {
    const line = typeof message === 'string' ? message : JSON.stringify(message) + '\n';
    sent += Buffer.byteLength(line); expectedHash.update(line);
    if (!child.stdin.write(line)) await once(child.stdin, 'drain');
  };
  const read = () => JSON.parse(fs.readFileSync(path.join(directory, fs.readdirSync(directory).find(name => name.endsWith('.json')))));
  const started = performance.now();
  try {
    const delta = JSON.stringify({ method: 'item/agentMessage/delta', params: { threadId: 'stress', delta: 'x'.repeat(1024) } }) + '\n';
    for (let index = 0; index < 100000; index++) await send(delta);
    for (let index = 0; index < 2000; index++) {
      const threadId = 'thread-' + index % 64, turnId = 'turn-' + index;
      await send({ method: 'turn/started', params: { threadId, turn: { id: turnId } } });
      await send({ id: index, method: 'item/tool/requestUserInput', params: { threadId, turnId, isBlocking: index % 2 === 0, questions: [{ id: 'q', question: '压力测试：' + 'x'.repeat(1024), options: [] }] } });
      await send({ method: 'serverRequest/resolved', params: { threadId, requestId: index } });
      await send({ method: 'turn/completed', params: { threadId, turn: { id: turnId, status: 'completed' } } });
    }
    const deadline = performance.now() + 30000;
    while (received < sent && performance.now() < deadline) await wait(50);
    assert.equal(received, sent, 'observer must drain all forwarded bytes');
    const burstMs = performance.now() - started;
    const state = read();
    assert.ok(state.threads.length <= 64);
    assert.ok(state.threads.every(thread => thread.questions.length === 0 && thread.blockingQuestions.length === 0 && thread.state === 'ended'));
    assert.ok(fs.statSync(path.join(directory, fs.readdirSync(directory).find(name => name.endsWith('.json')))).size < 512 * 1024);
    // Keep the process alive after the burst: sampling peak RSS alone misses
    // retained queues or polling work that persists after all tasks finish.
    await wait(10000);
    const idle = sample();
    assert.ok(peakRSS < 64 * 1024, `peak observer RSS ${peakRSS} KiB`);
    assert.ok(idle.cpu < 2, `observer did not return to idle: ${idle.cpu}%`);
    clearInterval(sampling);
    child.stdin.end();
    assert.equal(await closed, 0);
    assert.equal(actualHash.digest('hex'), expectedHash.digest('hex'));
    t.diagnostic(`${(sent / 1024 / 1024).toFixed(2)} MiB exact; burst ${burstMs.toFixed(0)} ms; sampled peak CPU ${peakCPU}%, peak RSS ${peakRSS} KiB; post-burst idle ${idle.cpu}% / ${idle.rss} KiB`);
  } finally {
    clearInterval(sampling);
    if (child.exitCode == null && child.signalCode == null) child.kill();
    await closed;
    fs.rmSync(root, { recursive: true, force: true });
  }
});
