#!/usr/bin/env node
// Local protocol echo fixture. No model calls, credentials or network.
const readline = require('node:readline');
if (!process.argv.includes('app-server')) { process.stdout.write('fixture-cli\n'); process.exit(0); }
readline.createInterface({ input: process.stdin }).on('line', line => {
  if (line === 'PID') {
    process.stdout.write(JSON.stringify({ fixturePID: process.pid }) + '\n');
  } else if (line === 'STRESS') {
    for (let i = 0; i < 10000; i++) process.stdout.write(JSON.stringify({ method: 'item/agentMessage/delta', params: { threadId: 't1', delta: 'x'.repeat(1024) } }) + '\n');
  } else { process.stdout.write(line + '\n'); }
});
