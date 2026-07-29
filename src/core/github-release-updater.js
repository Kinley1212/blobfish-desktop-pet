const fs = require('fs');
const path = require('path');
const { spawn: spawnChildProcess } = require('child_process');

const REPOSITORY = 'Kinley1212/blobfish-desktop-pet';
const LATEST_RELEASE_URL = `https://api.github.com/repos/${REPOSITORY}/releases/latest`;
const LATEST_MANIFEST_ASSET_NAME = 'blobfish-latest.json';
const LATEST_MANIFEST_URL = `https://github.com/${REPOSITORY}/releases/latest/download/${LATEST_MANIFEST_ASSET_NAME}`;
const MAX_RELEASE_ASSET_BYTES = 512 * 1024 * 1024;
const DEFAULT_STAGING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const DEFAULT_INSTALLER_WAIT_TIMEOUT_SECONDS = 120;
const DEFAULT_INSTALLER_COMMAND_TIMEOUT_SECONDS = 180;
const USER_AGENT_PRODUCT = 'blobfish-desktop-pet';

function parseVersion(value) {
  const match = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(String(value || '').trim());
  if (!match) return null;
  return match.slice(1).map(Number);
}

function normalizeVersion(value) {
  const parsed = parseVersion(value);
  return parsed ? parsed.join('.') : null;
}

function compareVersions(left, right) {
  const leftParts = parseVersion(left);
  const rightParts = parseVersion(right);
  if (!leftParts || !rightParts) return null;
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] !== rightParts[index]) return leftParts[index] - rightParts[index];
  }
  return 0;
}

function buildGitHubUserAgent(version) {
  return `${USER_AGENT_PRODUCT}/${normalizeVersion(version) || 'unknown'} (macOS updater)`;
}

function expectedAssetName(version, architecture) {
  if (!['arm64', 'x64'].includes(architecture)) throw new Error('不支持此 Mac 芯片类型');
  return `BlobfishPro-${version}-macOS-${architecture}.zip`;
}

function expectedAssetNames(version, architecture) {
  // Keep the new release asset name ASCII-only. The older Chinese and
  // GitHub-normalized names are still accepted so previously published releases
  // and already-generated local packages remain readable.
  return [
    expectedAssetName(version, architecture),
    `Pro${version}-macOS-${architecture}.zip`,
    `水滴鱼Pro${version}-macOS-${architecture}.zip`,
  ];
}

function parseSha256Digest(value) {
  const match = /^sha256:([a-f0-9]{64})$/i.exec(String(value || '').trim());
  return match ? match[1].toLowerCase() : null;
}

function isExpectedReleaseUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:'
      && url.hostname === 'github.com'
      && (
        url.pathname.startsWith(`/${REPOSITORY}/releases/download/`)
        || url.pathname.startsWith(`/${REPOSITORY}/releases/latest/download/`)
      );
  } catch {
    return false;
  }
}

function latestAssetDownloadUrl(assetName) {
  return `https://github.com/${REPOSITORY}/releases/latest/download/${encodeURIComponent(assetName)}`;
}

function selectReleaseUpdate(release, options) {
  if (!release || typeof release !== 'object') throw new Error('GitHub 返回的版本信息无效');
  if (release.draft || release.prerelease) throw new Error('GitHub 尚未发布可安装的正式版本');

  const version = normalizeVersion(release.tag_name);
  if (!version) throw new Error('GitHub 最新版本的标签格式无效');
  const currentVersion = normalizeVersion(options?.currentVersion);
  if (!currentVersion) throw new Error('当前应用版本格式无效');
  const comparison = compareVersions(version, currentVersion);
  if (comparison === null) throw new Error('无法比较应用版本');
  if (comparison <= 0) return { state: 'up-to-date', currentVersion, version };

  const assetNames = new Set(expectedAssetNames(version, options?.architecture));
  const asset = Array.isArray(release.assets) ? release.assets.find((item) => assetNames.has(item?.name)) : null;
  if (!asset) throw new Error(`Pro${version} 没有适用于这台 Mac 的完整安装包`);
  if (!Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > MAX_RELEASE_ASSET_BYTES) {
    throw new Error('GitHub 安装包大小异常，已停止更新');
  }
  if (!isExpectedReleaseUrl(asset.browser_download_url)) {
    throw new Error('GitHub 安装包下载地址无效，已停止更新');
  }
  const digest = parseSha256Digest(asset.digest);
  if (!digest) throw new Error('GitHub 安装包缺少 SHA-256 校验信息，无法安全自动更新');

  return {
    state: 'available',
    currentVersion,
    version,
    architecture: options.architecture,
    publishedAt: typeof release.published_at === 'string' ? release.published_at : null,
    releaseUrl: typeof release.html_url === 'string' ? release.html_url : null,
    asset: {
      name: asset.name,
      url: asset.browser_download_url,
      size: asset.size,
      digest,
      bundleName: `水滴鱼Pro${version}.app`,
    },
  };
}

function selectManifestUpdate(manifest, options) {
  if (!manifest || typeof manifest !== 'object') throw new Error('GitHub 更新清单无效');
  if (manifest.repository && manifest.repository !== REPOSITORY) throw new Error('GitHub 更新清单来源不匹配');

  const version = normalizeVersion(manifest.version || manifest.tag_name);
  if (!version) throw new Error('GitHub 更新清单的版本格式无效');
  const currentVersion = normalizeVersion(options?.currentVersion);
  if (!currentVersion) throw new Error('当前应用版本格式无效');
  const comparison = compareVersions(version, currentVersion);
  if (comparison === null) throw new Error('无法比较应用版本');
  if (comparison <= 0) return { state: 'up-to-date', currentVersion, version };

  const architecture = options?.architecture;
  if (!['arm64', 'x64'].includes(architecture)) throw new Error('不支持此 Mac 芯片类型');
  const asset = manifest.assets?.[architecture];
  if (!asset || typeof asset !== 'object') throw new Error(`Pro${version} 没有适用于这台 Mac 的完整安装包`);
  if (!expectedAssetNames(version, architecture).includes(asset.name)) {
    throw new Error('GitHub 更新清单的安装包名称无效，已停止更新');
  }
  if (!Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > MAX_RELEASE_ASSET_BYTES) {
    throw new Error('GitHub 安装包大小异常，已停止更新');
  }
  const url = asset.url || latestAssetDownloadUrl(asset.name);
  if (!isExpectedReleaseUrl(url)) {
    throw new Error('GitHub 安装包下载地址无效，已停止更新');
  }
  const digest = parseSha256Digest(asset.digest);
  if (!digest) throw new Error('GitHub 安装包缺少 SHA-256 校验信息，无法安全自动更新');

  return {
    state: 'available',
    currentVersion,
    version,
    architecture,
    publishedAt: typeof manifest.publishedAt === 'string' ? manifest.publishedAt : null,
    releaseUrl: typeof manifest.releaseUrl === 'string' ? manifest.releaseUrl : null,
    asset: {
      name: asset.name,
      url,
      size: asset.size,
      digest,
      bundleName: `水滴鱼Pro${version}.app`,
    },
  };
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function getInstalledAppBundle(executablePath) {
  if (!path.isAbsolute(executablePath)) throw new Error('无法确认当前应用位置');
  const executable = path.resolve(executablePath);
  const macosDirectory = path.dirname(executable);
  const contentsDirectory = path.dirname(macosDirectory);
  const bundlePath = path.dirname(contentsDirectory);
  if (path.basename(macosDirectory) !== 'MacOS'
    || path.basename(contentsDirectory) !== 'Contents'
    || path.extname(bundlePath) !== '.app') {
    throw new Error('当前不是可自动更新的应用程序包');
  }
  return bundlePath;
}

function resolveMacUpdateInstallTarget(options = {}) {
  const currentAppPath = options.currentAppPath;
  const bundleName = options.bundleName;
  const userApplicationsDirectory = options.userApplicationsDirectory;
  const fileSystem = options.fileSystem || fs;

  if (!path.isAbsolute(currentAppPath) || path.resolve(currentAppPath) !== currentAppPath) {
    throw new Error('无法确认当前应用位置');
  }
  if (
    typeof bundleName !== 'string'
    || path.basename(bundleName) !== bundleName
    || path.extname(bundleName) !== '.app'
  ) {
    throw new Error('新版应用程序名称无效');
  }

  const currentDirectory = path.dirname(currentAppPath);
  try {
    fileSystem.accessSync(currentDirectory, fs.constants.W_OK);
    return Object.freeze({
      targetAppPath: path.join(currentDirectory, bundleName),
      installLocation: 'current-directory',
      removeOldApp: true,
    });
  } catch {
    // A downloaded app can run from macOS App Translocation, and standard
    // accounts cannot normally write to the system /Applications directory.
    // In either case install the verified new bundle in the user's own
    // Applications folder instead of asking for administrator privileges.
  }

  if (
    !path.isAbsolute(userApplicationsDirectory)
    || path.resolve(userApplicationsDirectory) !== userApplicationsDirectory
  ) {
    throw new Error('无法确认个人应用程序文件夹');
  }
  try {
    fileSystem.mkdirSync(userApplicationsDirectory, { recursive: true, mode: 0o755 });
    fileSystem.accessSync(userApplicationsDirectory, fs.constants.W_OK);
  } catch {
    throw new Error('当前安装位置不可写，也无法使用个人“应用程序”文件夹');
  }

  return Object.freeze({
    targetAppPath: path.join(userApplicationsDirectory, bundleName),
    installLocation: 'user-applications',
    removeOldApp: false,
  });
}

function cleanupStaleUpdateStaging(updateRoot, options = {}) {
  if (!path.isAbsolute(updateRoot)) throw new Error('更新暂存目录必须是绝对路径');
  const resolvedRoot = path.resolve(updateRoot);
  const now = Number.isFinite(options.now) ? options.now : Date.now();
  const maxAgeMs = Number.isFinite(options.maxAgeMs)
    ? options.maxAgeMs
    : DEFAULT_STAGING_MAX_AGE_MS;
  if (maxAgeMs < 0) throw new Error('更新暂存目录保留时间无效');

  const activeDirectories = new Set((options.activeDirectories || []).map((directory) => {
    if (!path.isAbsolute(directory)) throw new Error('活动更新暂存目录必须是绝对路径');
    return path.resolve(directory);
  }));
  const result = {
    removed: [],
    skippedActive: [],
    skippedFresh: [],
    skippedUnsafe: [],
    failed: [],
  };
  let entries;
  try {
    entries = fs.readdirSync(resolvedRoot, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return result;
    throw error;
  }

  let claimSequence = 0;
  for (const entry of entries) {
    if (!entry.name.startsWith('release-') && !entry.name.startsWith('.cleanup-release-')) continue;
    const candidate = path.join(resolvedRoot, entry.name);
    if (activeDirectories.has(candidate)) {
      result.skippedActive.push(candidate);
      continue;
    }

    let stat;
    try {
      stat = fs.lstatSync(candidate);
    } catch (error) {
      if (error.code !== 'ENOENT') result.failed.push({ path: candidate, code: error.code || 'UNKNOWN' });
      continue;
    }
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      result.skippedUnsafe.push(candidate);
      continue;
    }
    if ((now - stat.mtimeMs) < maxAgeMs) {
      result.skippedFresh.push(candidate);
      continue;
    }

    // Atomically claim the exact directory before deleting it. A concurrent
    // updater can create a new directory at the original path without that new
    // directory being caught by this cleanup pass.
    claimSequence += 1;
    const claimed = path.join(
      resolvedRoot,
      `.cleanup-${entry.name}-${process.pid}-${claimSequence}`,
    );
    try {
      fs.renameSync(candidate, claimed);
      const claimedStat = fs.lstatSync(claimed);
      if (!claimedStat.isDirectory()
        || claimedStat.isSymbolicLink()
        || claimedStat.dev !== stat.dev
        || claimedStat.ino !== stat.ino) {
        result.skippedUnsafe.push(candidate);
        continue;
      }
      fs.rmSync(claimed, { recursive: true, force: true, maxRetries: 2, retryDelay: 50 });
      result.removed.push(candidate);
    } catch (error) {
      result.failed.push({ path: candidate, code: error.code || 'UNKNOWN' });
    }
  }
  return result;
}

async function withUpdateTimeout(label, timeoutMs, operation) {
  if (typeof operation !== 'function') throw new TypeError('更新操作无效');
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) throw new Error('更新操作超时时间无效');
  const timeoutLabel = String(label || '更新操作').trim() || '更新操作';
  const controller = new AbortController();
  let timeoutHandle;
  const timeoutPromise = new Promise((resolve, reject) => {
    timeoutHandle = setTimeout(() => {
      const error = new Error(`${timeoutLabel}超时，已取消。请检查网络后重试`);
      controller.abort(error);
      reject(error);
    }, timeoutMs);
  });

  try {
    return await Promise.race([
      Promise.resolve().then(() => operation(controller.signal)),
      timeoutPromise,
    ]);
  } finally {
    clearTimeout(timeoutHandle);
  }
}

function validatePositiveInteger(value, fallback, label) {
  const resolved = value === undefined ? fallback : value;
  if (!Number.isInteger(resolved) || resolved <= 0) throw new Error(`${label}无效`);
  return resolved;
}

function buildMacInstallerScript(options) {
  const requiredPaths = ['zipPath', 'stagingDirectory', 'currentAppPath', 'targetAppPath'];
  for (const key of requiredPaths) {
    if (!path.isAbsolute(options?.[key])) throw new Error(`安装路径无效：${key}`);
    if (path.resolve(options[key]) !== options[key]) throw new Error(`安装路径必须是规范绝对路径：${key}`);
  }
  if (!Number.isInteger(options?.processId) || options.processId <= 0) throw new Error('安装进程信息无效');
  if (path.extname(options.currentAppPath) !== '.app' || path.extname(options.targetAppPath) !== '.app') {
    throw new Error('应用程序包路径无效');
  }
  if (options.currentAppPath === options.targetAppPath) throw new Error('新旧应用程序包路径不能相同');
  const sameInstallDirectory = path.dirname(options.currentAppPath) === path.dirname(options.targetAppPath);
  const removeOldApp = options.removeOldApp === undefined
    ? sameInstallDirectory
    : Boolean(options.removeOldApp);
  if (removeOldApp && !sameInstallDirectory) {
    throw new Error('不能从其他文件夹自动移除旧版本');
  }
  if (path.dirname(options.zipPath) !== options.stagingDirectory) {
    throw new Error('更新压缩包必须位于暂存目录');
  }
  if (!path.basename(options.stagingDirectory).startsWith('release-')) {
    throw new Error('更新暂存目录名称无效');
  }
  const versionMatch = /(\d+\.\d+\.\d+)$/.exec(path.basename(options.targetAppPath, '.app'));
  const expectedVersion = normalizeVersion(options.expectedVersion || versionMatch?.[1]);
  if (!expectedVersion || (versionMatch && expectedVersion !== versionMatch[1])) {
    throw new Error('目标应用版本无效');
  }
  const waitTimeoutSeconds = validatePositiveInteger(
    options.waitTimeoutSeconds,
    DEFAULT_INSTALLER_WAIT_TIMEOUT_SECONDS,
    '等待旧版本退出的超时时间',
  );
  const commandTimeoutSeconds = validatePositiveInteger(
    options.commandTimeoutSeconds,
    DEFAULT_INSTALLER_COMMAND_TIMEOUT_SECONDS,
    '安装命令超时时间',
  );
  const extractedAppPath = path.join(options.stagingDirectory, 'extracted', path.basename(options.targetAppPath));
  return `#!/bin/zsh
set -eu

old_app=${shellQuote(options.currentAppPath)}
new_app=${shellQuote(options.targetAppPath)}
archive=${shellQuote(options.zipPath)}
staging=${shellQuote(options.stagingDirectory)}
source_app=${shellQuote(extractedAppPath)}
expected_version=${shellQuote(expectedVersion)}
old_pid=${options.processId}
remove_old_app=${removeOldApp ? 1 : 0}
install_app="\${new_app}.installing-\${old_pid}-$$"
install_promoted=0
install_succeeded=0
RUN_WITH_TIMEOUT_TIMED_OUT=0
active_command_pid=0
active_watchdog_pid=0

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if (( active_watchdog_pid > 0 )); then
    /bin/kill -TERM "$active_watchdog_pid" 2>/dev/null || true
    wait "$active_watchdog_pid" 2>/dev/null || true
  fi
  if (( active_command_pid > 0 )); then
    /bin/kill -TERM "$active_command_pid" 2>/dev/null || true
    /bin/sleep 0.2
    /bin/kill -KILL "$active_command_pid" 2>/dev/null || true
    wait "$active_command_pid" 2>/dev/null || true
  fi
  if [[ -e "$install_app" ]]; then
    /bin/chmod -R u+w "$install_app" 2>/dev/null || true
    /bin/rm -R "$install_app" 2>/dev/null || true
  fi
  if (( install_promoted == 1 && install_succeeded == 0 )) && [[ -e "$new_app" ]]; then
    /bin/chmod -R u+w "$new_app" 2>/dev/null || true
    /bin/rm -R "$new_app" 2>/dev/null || true
  fi
  if [[ -d "$staging" ]]; then
    /bin/chmod -R u+w "$staging" 2>/dev/null || true
    /bin/rm -R "$staging" 2>/dev/null || true
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

run_with_timeout() {
  local timeout_seconds=$1
  shift
  local timeout_marker="$staging/.command-timeout-$$"
  local command_status=0
  RUN_WITH_TIMEOUT_TIMED_OUT=0
  /bin/rm -f "$timeout_marker"
  "$@" &
  active_command_pid=$!
  local command_pid=$active_command_pid
  (
    /bin/sleep "$timeout_seconds"
    if /bin/kill -0 "$command_pid" 2>/dev/null; then
      : > "$timeout_marker"
      /bin/kill -TERM "$command_pid" 2>/dev/null || true
      /bin/sleep 2
      /bin/kill -KILL "$command_pid" 2>/dev/null || true
    fi
  ) &
  active_watchdog_pid=$!
  local watchdog_pid=$active_watchdog_pid
  wait "$command_pid" || command_status=$?
  /bin/kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  active_command_pid=0
  active_watchdog_pid=0
  if [[ -e "$timeout_marker" ]]; then
    RUN_WITH_TIMEOUT_TIMED_OUT=1
    /bin/rm -f "$timeout_marker"
    return 124
  fi
  return "$command_status"
}

old_process_deadline=$((SECONDS + ${waitTimeoutSeconds}))
while /bin/kill -0 "$old_pid" 2>/dev/null; do
  if (( SECONDS >= old_process_deadline )); then
    echo "等待旧版本退出超时，已取消安装。" >&2
    exit 1
  fi
  /bin/sleep 0.2
done

/bin/mkdir -p "$staging/extracted"
if ! run_with_timeout ${commandTimeoutSeconds} /usr/bin/ditto -x -k --sequesterRsrc "$archive" "$staging/extracted"; then
  if (( RUN_WITH_TIMEOUT_TIMED_OUT == 1 )); then
    echo "解压更新包超时，已取消安装。" >&2
  else
    echo "解压更新包失败，已取消安装。" >&2
  fi
  exit 1
fi
if [[ ! -d "$source_app" ]]; then
  echo "更新包内没有预期的应用程序：$source_app" >&2
  exit 1
fi
old_info="$old_app/Contents/Info.plist"
source_info="$source_app/Contents/Info.plist"
if [[ ! -f "$old_info" || ! -f "$source_info" ]]; then
  echo "更新包缺少应用信息，已取消安装。" >&2
  exit 1
fi
old_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$old_info" 2>/dev/null || true)
source_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_info" 2>/dev/null || true)
source_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_info" 2>/dev/null || true)
old_executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$old_info" 2>/dev/null || true)
source_executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$source_info" 2>/dev/null || true)
old_executable="$old_app/Contents/MacOS/$old_executable_name"
source_executable="$source_app/Contents/MacOS/$source_executable_name"
if [[ -z "$old_bundle_id" || "$source_bundle_id" != "$old_bundle_id" ]]; then
  echo "更新包的应用身份不匹配，已取消安装。" >&2
  exit 1
fi
if [[ "$source_version" != "$expected_version" ]]; then
  echo "更新包的版本不匹配，已取消安装。" >&2
  exit 1
fi
if [[ ! -x "$old_executable" || ! -x "$source_executable" ]]; then
  echo "更新包的主程序无效，已取消安装。" >&2
  exit 1
fi
old_arches=$(/usr/bin/lipo -archs "$old_executable" 2>/dev/null || true)
source_arches=$(/usr/bin/lipo -archs "$source_executable" 2>/dev/null || true)
if [[ -z "$old_arches" || -z "$source_arches" ]]; then
  echo "无法确认更新包的芯片架构，已取消安装。" >&2
  exit 1
fi
for required_arch in \${(z)old_arches}; do
  if [[ " $source_arches " != *" $required_arch "* ]]; then
    echo "更新包的芯片架构不匹配，已取消安装。" >&2
    exit 1
  fi
done
if ! run_with_timeout ${commandTimeoutSeconds} /usr/bin/codesign --verify --deep --strict "$source_app"; then
  echo "更新包签名验证失败或超时，已取消安装。" >&2
  exit 1
fi
if [[ -e "$new_app" ]]; then
  echo "目标版本已经存在：$new_app" >&2
  exit 1
fi
if ! run_with_timeout ${commandTimeoutSeconds} /usr/bin/ditto "$source_app" "$install_app"; then
  if (( RUN_WITH_TIMEOUT_TIMED_OUT == 1 )); then
    echo "复制新版本超时，已取消安装。" >&2
  else
    echo "复制新版本失败，已取消安装。" >&2
  fi
  exit 1
fi
if ! run_with_timeout ${commandTimeoutSeconds} /usr/bin/codesign --verify --deep --strict "$install_app"; then
  echo "复制后的应用签名验证失败或超时，已取消安装。" >&2
  exit 1
fi
if [[ -e "$new_app" ]]; then
  echo "安装位置在更新期间发生变化，已取消安装。" >&2
  exit 1
fi
if ! /bin/mv -n "$install_app" "$new_app"; then
  echo "无法将新版本放入安装位置，已取消安装。" >&2
  exit 1
fi
if [[ -e "$install_app" || ! -d "$new_app" ]]; then
  echo "安装位置在更新期间被占用，已取消安装。" >&2
  exit 1
fi
install_promoted=1
if ! run_with_timeout 30 /usr/bin/open "$new_app"; then
  echo "无法启动新版本，已回滚安装。" >&2
  exit 1
fi
install_succeeded=1
if (( remove_old_app == 1 )); then
  run_with_timeout 30 /usr/bin/osascript - "$old_app" <<'APPLESCRIPT' || true
on run argv
  tell application "Finder" to delete POSIX file (item 1 of argv)
end run
APPLESCRIPT
fi
`;
}

function launchMacInstallerInBackground(commandPath, options = {}) {
  if (!path.isAbsolute(commandPath) || path.resolve(commandPath) !== commandPath) {
    return Promise.reject(new Error('更新安装器路径无效'));
  }
  if (
    path.extname(commandPath) !== '.command'
    || !path.basename(path.dirname(commandPath)).startsWith('release-')
  ) {
    return Promise.reject(new Error('更新安装器不在受信任的暂存目录'));
  }
  const spawn = options.spawn || spawnChildProcess;
  if (typeof spawn !== 'function') return Promise.reject(new TypeError('更新安装器启动方式无效'));

  return new Promise((resolve, reject) => {
    let child;
    try {
      // Invoke zsh directly instead of asking Finder to open a .command file.
      // This keeps Terminal out of sight while preserving the constrained,
      // auditable installer script and all of its validation/rollback checks.
      child = spawn('/bin/zsh', [commandPath], {
        detached: true,
        shell: false,
        stdio: 'ignore',
        windowsHide: true,
      });
    } catch (error) {
      reject(error);
      return;
    }
    child.once('error', reject);
    child.once('spawn', () => {
      child.unref();
      resolve();
    });
  });
}

module.exports = {
  LATEST_RELEASE_URL,
  LATEST_MANIFEST_ASSET_NAME,
  LATEST_MANIFEST_URL,
  MAX_RELEASE_ASSET_BYTES,
  REPOSITORY,
  buildMacInstallerScript,
  buildGitHubUserAgent,
  cleanupStaleUpdateStaging,
  compareVersions,
  expectedAssetName,
  expectedAssetNames,
  getInstalledAppBundle,
  isExpectedReleaseUrl,
  latestAssetDownloadUrl,
  launchMacInstallerInBackground,
  normalizeVersion,
  parseSha256Digest,
  resolveMacUpdateInstallTarget,
  selectManifestUpdate,
  selectReleaseUpdate,
  withUpdateTimeout,
};
