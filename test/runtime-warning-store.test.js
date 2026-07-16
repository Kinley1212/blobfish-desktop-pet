const assert = require('node:assert/strict');
const test = require('node:test');

const { RuntimeWarningStore } = require('../src/core/runtime-warning-store');

test('clearing one successful subsystem preserves unrelated warnings', () => {
  const warnings = new RuntimeWarningStore();
  warnings.set('character', '形象包无法加载');
  warnings.set('language', '语言包无法加载');
  warnings.clear('language');
  assert.equal(warnings.getMessage(), '形象包无法加载');
});

test('combines runtime and configuration warnings without inventing empty output', () => {
  const warnings = new RuntimeWarningStore();
  warnings.set('startup', '登录启动设置失败');
  assert.equal(warnings.getMessage('配置文件已恢复默认'), '登录启动设置失败\n配置文件已恢复默认');
  warnings.clear('startup');
  assert.equal(warnings.getMessage(), null);
});
