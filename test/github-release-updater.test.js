const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('path');
const {
  buildMacInstallerScript,
  buildGitHubUserAgent,
  cleanupStaleUpdateStaging,
  compareVersions,
  expectedAssetNames,
  getInstalledAppBundle,
  latestAssetDownloadUrl,
  launchMacInstallerInBackground,
  selectManifestUpdate,
  selectReleaseUpdate,
  withUpdateTimeout,
} = require('../src/core/github-release-updater');

const DIGEST = 'a'.repeat(64);

function release(overrides = {}) {
  return {
    tag_name: 'v1.2.1',
    html_url: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/tag/v1.2.1',
    published_at: '2026-07-27T08:00:00Z',
    assets: [{
      name: 'BlobfishPro-1.2.1-macOS-arm64.zip',
      size: 123456,
      digest: `sha256:${DIGEST}`,
      browser_download_url: 'https://github.com/Kinley1212/blobfish-desktop-pet/releases/download/v1.2.1/BlobfishPro-1.2.1-macOS-arm64.zip',
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
        name: 'BlobfishPro-1.2.4-macOS-arm64.zip',
        size: 123456,
        digest: `sha256:${DIGEST}`,
      },
      x64: {
        name: 'BlobfishPro-1.2.4-macOS-x64.zip',
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

test('uses an ASCII-only release asset name and keeps old names compatible', () => {
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
    'BlobfishPro-1.2.1-macOS-arm64.zip',
    'Pro1.2.1-macOS-arm64.zip',
    '水滴鱼Pro1.2.1-macOS-arm64.zip',
  ]);
});

test('selects updates from the downloadable manifest without using the GitHub API', () => {
  const result = selectManifestUpdate(manifest(), { currentVersion: '1.2.3', architecture: 'arm64' });

  assert.equal(result.state, 'available');
  assert.equal(result.version, '1.2.4');
  assert.equal(result.asset.name, 'BlobfishPro-1.2.4-macOS-arm64.zip');
  assert.equal(result.asset.url, latestAssetDownloadUrl('BlobfishPro-1.2.4-macOS-arm64.zip'));
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

test('installer script bounds subprocesses and atomically promotes a verified app', () => {
  const oldApp = '/Applications/水滴鱼Pro1.2.0.app';
  const newApp = '/Applications/水滴鱼Pro1.2.1.app';
  const staging = '/tmp/updates/release-abc123';
  const script = buildMacInstallerScript({
    currentAppPath: oldApp,
    targetAppPath: newApp,
    zipPath: path.join(staging, '水滴鱼Pro1.2.1-macOS-arm64.zip'),
    stagingDirectory: staging,
    processId: 123,
  });
  assert.match(script, /while \/bin\/kill -0/);
  assert.match(script, /old_process_deadline=/);
  assert.match(script, /run_with_timeout/);
  assert.match(script, /\/usr\/bin\/ditto -x -k --sequesterRsrc/);
  assert.match(script, /source_app='\/tmp\/updates\/release-abc123\/extracted\/水滴鱼Pro1\.2\.1\.app'/);
  assert.match(script, /\/usr\/bin\/codesign --verify --deep --strict/);
  assert.match(script, /\/usr\/bin\/lipo -archs/);
  assert.match(script, /install_app=/);
  assert.match(script, /active_command_pid=/);
  assert.match(script, /\/bin\/kill -TERM "\$active_command_pid"/);
  assert.match(script, /\/bin\/mv -n "\$install_app" "\$new_app"/);
  assert.match(script, /if \[\[ -e "\$install_app" \]\]/);
  assert.match(script, /trap cleanup EXIT/);
  assert.match(script, /\/bin\/rm -R "\$staging"/);
  assert.match(script, /tell application "Finder" to delete POSIX file/);
  assert.doesNotMatch(script, /\/bin\/cp -R/);
});

test('launches the verified installer as a hidden detached helper instead of opening Terminal', async () => {
  const commandPath = '/tmp/updates/release-abc123/安装水滴鱼更新.command';
  const calls = [];
  let unrefCount = 0;
  const listeners = {};
  const child = {
    once(event, callback) {
      listeners[event] = callback;
      return this;
    },
    unref() {
      unrefCount += 1;
    },
  };
  const spawn = (...args) => {
    calls.push(args);
    queueMicrotask(() => listeners.spawn());
    return child;
  };

  await launchMacInstallerInBackground(commandPath, { spawn });

  assert.deepEqual(calls, [[
    '/bin/zsh',
    [commandPath],
    {
      detached: true,
      shell: false,
      stdio: 'ignore',
      windowsHide: true,
    },
  ]]);
  assert.equal(unrefCount, 1);
});

test('rejects an installer outside the private release staging directory', async () => {
  await assert.rejects(
    launchMacInstallerInBackground('/tmp/installer.command', {
      spawn: () => {
        throw new Error('must not spawn');
      },
    }),
    /不在受信任的暂存目录/,
  );
});

test('cleans only old release staging directories and leaves fresh, active and unsafe entries alone', () => {
  const updateRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-update-cleanup-'));
  const oldDirectory = path.join(updateRoot, 'release-old');
  const activeDirectory = path.join(updateRoot, 'release-active');
  const freshDirectory = path.join(updateRoot, 'release-fresh');
  const unrelatedDirectory = path.join(updateRoot, 'other-old');
  const symlink = path.join(updateRoot, 'release-link');
  const abandonedClaim = path.join(updateRoot, '.cleanup-release-abandoned');
  fs.mkdirSync(oldDirectory);
  fs.mkdirSync(activeDirectory);
  fs.mkdirSync(freshDirectory);
  fs.mkdirSync(unrelatedDirectory);
  fs.mkdirSync(abandonedClaim);
  fs.symlinkSync(oldDirectory, symlink);
  const oldDate = new Date(Date.now() - (48 * 60 * 60 * 1000));
  fs.utimesSync(oldDirectory, oldDate, oldDate);
  fs.utimesSync(activeDirectory, oldDate, oldDate);
  fs.utimesSync(unrelatedDirectory, oldDate, oldDate);
  fs.utimesSync(abandonedClaim, oldDate, oldDate);

  try {
    const result = cleanupStaleUpdateStaging(updateRoot, {
      now: Date.now(),
      maxAgeMs: 24 * 60 * 60 * 1000,
      activeDirectories: [activeDirectory],
    });

    assert.deepEqual([...result.removed].sort(), [abandonedClaim, oldDirectory].sort());
    assert.equal(fs.existsSync(oldDirectory), false);
    assert.equal(fs.existsSync(activeDirectory), true);
    assert.equal(fs.existsSync(freshDirectory), true);
    assert.equal(fs.existsSync(unrelatedDirectory), true);
    assert.equal(fs.existsSync(abandonedClaim), false);
    assert.equal(fs.lstatSync(symlink).isSymbolicLink(), true);
    assert.equal(result.skippedUnsafe.includes(symlink), true);
  } finally {
    fs.rmSync(updateRoot, { recursive: true, force: true });
  }
});

test('reports an explicit timeout and aborts the whole update operation', async () => {
  let receivedSignal = null;
  await assert.rejects(
    withUpdateTimeout('下载更新包', 5, (signal) => {
      receivedSignal = signal;
      return new Promise((resolve, reject) => {
        signal.addEventListener('abort', () => reject(signal.reason), { once: true });
      });
    }),
    /下载更新包超时/,
  );
  assert.equal(receivedSignal.aborted, true);
});

test('clears the timeout when an update operation completes', async () => {
  const result = await withUpdateTimeout('检查更新', 1000, async (signal) => {
    assert.equal(signal.aborted, false);
    return 'ok';
  });
  assert.equal(result, 'ok');
});
