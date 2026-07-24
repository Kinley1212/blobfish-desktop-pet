const path = require('path');

const REPOSITORY = 'Kinley1212/blobfish-desktop-pet';
const LATEST_RELEASE_URL = `https://api.github.com/repos/${REPOSITORY}/releases/latest`;
const MAX_RELEASE_ASSET_BYTES = 512 * 1024 * 1024;

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

function expectedAssetName(version, architecture) {
  if (!['arm64', 'x64'].includes(architecture)) throw new Error('不支持此 Mac 芯片类型');
  return `水滴鱼Pro${version}-macOS-${architecture}.zip`;
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
      && url.pathname.startsWith(`/${REPOSITORY}/releases/download/`);
  } catch {
    return false;
  }
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

  const assetName = expectedAssetName(version, options?.architecture);
  const asset = Array.isArray(release.assets) ? release.assets.find((item) => item?.name === assetName) : null;
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

function buildMacInstallerScript(options) {
  const requiredPaths = ['zipPath', 'stagingDirectory', 'currentAppPath', 'targetAppPath'];
  for (const key of requiredPaths) {
    if (!path.isAbsolute(options?.[key])) throw new Error(`安装路径无效：${key}`);
  }
  if (!Number.isInteger(options?.processId) || options.processId <= 0) throw new Error('安装进程信息无效');
  if (path.extname(options.currentAppPath) !== '.app' || path.extname(options.targetAppPath) !== '.app') {
    throw new Error('应用程序包路径无效');
  }
  if (path.dirname(options.currentAppPath) !== path.dirname(options.targetAppPath)) {
    throw new Error('新旧应用必须安装到同一文件夹');
  }
  const extractedAppPath = path.join(options.stagingDirectory, 'extracted', path.basename(options.targetAppPath));
  return `#!/bin/zsh
set -eu

old_app=${shellQuote(options.currentAppPath)}
new_app=${shellQuote(options.targetAppPath)}
archive=${shellQuote(options.zipPath)}
staging=${shellQuote(options.stagingDirectory)}
source_app=${shellQuote(extractedAppPath)}
old_pid=${options.processId}

while /bin/kill -0 "$old_pid" 2>/dev/null; do
  /bin/sleep 0.2
done

/bin/mkdir -p "$staging/extracted"
/usr/bin/ditto -x -k --sequesterRsrc "$archive" "$staging/extracted"
if [[ ! -d "$source_app" ]]; then
  echo "更新包内没有预期的应用程序：$source_app" >&2
  exit 1
fi
if [[ -e "$new_app" ]]; then
  echo "目标版本已经存在：$new_app" >&2
  exit 1
fi
/usr/bin/ditto "$source_app" "$new_app"
/usr/bin/open "$new_app"
/usr/bin/osascript - "$old_app" <<'APPLESCRIPT' || true
on run argv
  tell application "Finder" to delete POSIX file (item 1 of argv)
end run
APPLESCRIPT
`;
}

module.exports = {
  LATEST_RELEASE_URL,
  MAX_RELEASE_ASSET_BYTES,
  REPOSITORY,
  buildMacInstallerScript,
  compareVersions,
  expectedAssetName,
  getInstalledAppBundle,
  isExpectedReleaseUrl,
  normalizeVersion,
  parseSha256Digest,
  selectReleaseUpdate,
};
