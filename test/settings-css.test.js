const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const css = fs.readFileSync(path.join(__dirname, '..', 'src', 'styles', 'settings.css'), 'utf8');

test('settings navigation owns its height and is excluded from generic action button styles', () => {
  assert.match(css, /\.nav-item\s*\{[\s\S]*?height:\s*auto;[\s\S]*?min-height:\s*52px;/);
  assert.match(css, /button:not\(\.nav-item\)\s*\{/);
  assert.doesNotMatch(css, /(?:^|\n)button\s*\{\s*\n\s*min-width:/);
});
