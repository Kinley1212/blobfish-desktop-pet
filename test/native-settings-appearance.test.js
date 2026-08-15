const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const settingsSource = fs.readFileSync(
  path.join(__dirname, '..', 'native-appkit', 'Sources', 'BlobfishNative', 'SettingsWindowController.swift'),
  'utf8',
);
const viewStart = settingsSource.indexOf('struct BrandedSettingsView: View');
const viewEnd = settingsSource.indexOf('final class SettingsWindowController');
const viewSource = settingsSource.slice(viewStart, viewEnd);

test('native settings surfaces use system-adaptive colors and materials', () => {
  assert.notEqual(viewStart, -1);
  assert.notEqual(viewEnd, -1);
  assert.match(settingsSource, /Color\(nsColor: \.windowBackgroundColor\)/);
  assert.match(settingsSource, /Color\(nsColor: \.controlBackgroundColor\)/);
  assert.match(settingsSource, /Color\(nsColor: \.textBackgroundColor\)/);
  assert.match(settingsSource, /Color\(nsColor: \.separatorColor\)/);
  assert.match(settingsSource, /Color\(nsColor: \.quaternaryLabelColor\)/);
  assert.match(viewSource, /\.background\(SettingsSurfacePalette\.windowBackground\)/);
  assert.match(viewSource, /\.background\(\.thinMaterial\)/);
  assert.match(viewSource, /\.background\(\.regularMaterial\)/);
  assert.match(viewSource, /SettingsSurfacePalette\.controlBackground/);
  assert.match(viewSource, /SettingsSurfacePalette\.previewBackground/);
  assert.match(viewSource, /SettingsSurfacePalette\.subtleFill/);
  assert.match(viewSource, /SettingsSurfacePalette\.separator/);
});

test('native settings surfaces do not reintroduce fixed light fills', () => {
  assert.doesNotMatch(viewSource, /\.background\(\s*Color\.white\b/);
  assert.doesNotMatch(viewSource, /Color\.black\b/);
  assert.doesNotMatch(
    viewSource,
    /colors:\s*\[\s*Color\(red:\s*0\.95[\s\S]*?Color\(red:\s*0\.98/,
  );
});
