const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const {
  buildMacInstallerScript,
  buildGitHubUserAgent,
  compareVersions,
  expectedAssetNames,
  getInstalledAppBundle,
  latestAssetDownloadUrl,
  selectManifestUpdate,
  selectReleaseUpdate,
} = require('../src/core/github-release-updater');

const DIGEST = 'a'.repeat(64);

function release(overrides = {}) {
  return {
    tag_name: 'v1.2.1',
    html_url: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/tag/v1.2.1',
    published_at: '2026-07-27T08:00:00Z',
    assets: [{
      name: '水滴鱼Pro1.2.1-macOS-arm64.zip',
      size: 123456,
      digest: `sha256:${DIGEST}`,
      browser_download_url: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/download/v1.2.1/%E6%B0%B4%E6%BB%B4%E9%B1%BCPro1.2.1-macOS-arm64.zip',
    }],
    ...overrides,
  };
}

function manifest(overrides = {}) {
  return {
    version: '1.2.4',
    repository: 'Kinley1212/blobfish-desktop-pet',
    releaseUrl: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/tag/v1.2.4',
    assets: {
      arm64: {
        name: 'Pro1.2.4-macOS-arm64.zip',
        size: 123456,
        digest: `sha256:${DIGEST}`,
      },
      x64: {
        name: 'Pro1.2.4-macOS-x64.zip',
        size: 223456,
        digest: `sha256:${'b'.repeat(64)}`,
      },
    },
    ...overrides,
  };
}

test('selects only the matching GitHub release asset and reports a newer version', () => {
  const result = selectReleaseUpdate(release(), { currentVersion: '1.2.0', architecture: 'arm64' });
  assert.equal(result.state, 'available');
  assert.equal(result.version, '1.2.1');
  assert.equal(result.asset.bundleName, '水滴鱼Pro1.2.1.app');
  assert.equal(result.asset.digest, DIGEST);
});

test('accepts the ASCII filename GitHub keeps after normalizing a Chinese asset name', () => {
  const result = selectReleaseUpdate(release({
    assets: [{
      ...release().assets[0],
      name: 'Pro1.2.1-macOS-arm64.zip',
      browser_download_url: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/download/v1.2.1/Pro1.2.1-macOS-arm64.zip',
    }],
  }), { currentVersion: '1.2.0', architecture: 'arm64' });

  assert.equal(result.state, 'available');
  assert.equal(result.asset.name, 'Pro1.2.1-macOS-arm64.zip');
  assert.deepEqual(expectedAssetNames('1.2.1', 'arm64'), [
    '水滴鱼Pro1.2.1-macOS-arm64.zip',
    'Pro1.2.1-macOS-arm64.zip',
  ]);
});

test('selects updates from the downloadable manifest without using the GitHub API', () => {
  const result = selectManifestUpdate(manifest(), { currentVersion: '1.2.3', architecture: 'arm64' });

  assert.equal(result.state, 'available');
  assert.equal(result.version, '1.2.4');
  assert.equal(result.asset.name, 'Pro1.2.4-macOS-arm64.zip');
  assert.equal(result.asset.url, latestAssetDownloadUrl('Pro1.2.4-macOS-arm64.zip'));
  assert.equal(result.asset.digest, DIGEST);
});

test('rejects manifest assets that do not match the version, architecture or repository', () => {
  assert.throws(
    () => selectManifestUpdate(manifest({ repository: 'someone/else' }), { currentVersion: '1.2.3', architecture: 'arm64' }),
    /来源不匹配/,
  );
  assert.throws(
    () => selectManifestUpdate(manifest({
      assets: { arm64: { ...manifest().assets.arm64, name: 'Pro1.2.5-macOS-arm64.zip' } },
    }), { currentVersion: '1.2.3', architecture: 'arm64' }),
    /名称无效/,
  );
  assert.throws(
    () => selectManifestUpdate(manifest({
      assets: { arm64: { ...manifest().assets.arm64, url: 'https://example.com/blobfish.zip' } },
    }), { currentVersion: '1.2.3', architecture: 'arm64' }),
    /下载地址无效/,
  );
});

test('does not offer an update when the latest version is already installed', () => {
  const result = selectReleaseUpdate(release(), { currentVersion: '1.2.1', architecture: 'arm64' });
  assert.deepEqual(result, { state: 'up-to-date', currentVersion: '1.2.1', version: '1.2.1' });
});

test('rejects a release asset without a matching SHA-256 digest or trusted URL', () => {
  assert.throws(
    () => selectReleaseUpdate(release({ assets: [{ ...release().assets[0], digest: null }] }), { currentVersion: '1.2.0', architecture: 'arm64' }),
    /SHA-256/,
  );
  assert.throws(
    () => selectReleaseUpdate(release({ assets: [{ ...release().assets[0], browser_download_url: 'https://example.com/update.zip' }] }), { currentVersion: '1.2.0', architecture: 'arm64' }),
    /下载地址无效/,
  );
});

test('rejects drafts, prereleases, and missing architecture assets', () => {
  assert.throws(() => selectReleaseUpdate(release({ draft: true }), { currentVersion: '1.2.0', architecture: 'arm64' }), /正式版本/);
  assert.throws(() => selectReleaseUpdate(release({ prerelease: true }), { currentVersion: '1.2.0', architecture: 'arm64' }), /正式版本/);
  assert.throws(() => selectReleaseUpdate(release(), { currentVersion: '1.2.0', architecture: 'x64' }), /完整安装包/);
});

test('compares stable semantic versions only', () => {
  assert.ok(compareVersions('1.2.1', '1.2.0') > 0);
  assert.equal(compareVersions('v1.2.1', '1.2.1'), 0);
  assert.equal(compareVersions('1.2', '1.2.1'), null);
});

test('uses an ASCII-only GitHub user agent', () => {
  const userAgent = buildGitHubUserAgent('1.2.1');
  assert.equal(userAgent, 'blobfish-desktop-pet/1.2.1 (macOS updater)');
  assert.doesNotMatch(userAgent, /[^\x20-\x7e]/);
  assert.doesNotMatch(buildGitHubUserAgent('水滴鱼Pro1.2.1'), /[^\x20-\x7e]/);
});

test('derives an app bundle only from a normal macOS executable location', () => {
  const executable = '/Applications/水滴鱼Pro1.2.0.app/Contents/MacOS/水滴鱼Pro1.2.0';
  assert.equal(getInstalledAppBundle(executable), '/Applications/水滴鱼Pro1.2.0.app');
  assert.throws(() => getInstalledAppBundle('/tmp/waterfish'), /可自动更新/);
});

test('installer script waits for the old process, extracts a precise bundle, then trashes only the old app', () => {
  const oldApp = '/Applications/水滴鱼Pro1.2.0.app';
  const newApp = '/Applications/水滴鱼Pro1.2.1.app';
  const staging = '/tmp/blobfish-update-a';
  const script = buildMacInstallerScript({
    currentAppPath: oldApp,
    targetAppPath: newApp,
    zipPath: path.join(staging, '水滴鱼Pro1.2.1-macOS-arm64.zip'),
    stagingDirectory: staging,
    processId: 123,
  });
  assert.match(script, /while \/bin\/kill -0/);
  assert.match(script, /\/usr\/bin\/ditto -x -k --sequesterRsrc/);
  assert.match(script, /source_app='\/tmp\/blobfish-update-a\/extracted\/水滴鱼Pro1\.2\.1\.app'/);
  assert.match(script, /tell application "Finder" to delete POSIX file/);
  assert.doesNotMatch(script, /rm -rf/);
});
