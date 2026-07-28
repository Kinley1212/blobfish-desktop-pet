const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const packageManifest = require('../package.json');
const { LATEST_MANIFEST_ASSET_NAME, REPOSITORY, latestAssetDownloadUrl } = require('../src/core/github-release-updater');

const root = path.join(__dirname, '..');
const releaseDirectory = path.join(root, 'release');
const version = packageManifest.version;

function assetEntry(architecture) {
  const githubName = `BlobfishPro-${version}-macOS-${architecture}.zip`;
  const localPath = path.join(releaseDirectory, githubName);
  const buffer = fs.readFileSync(localPath);
  return {
    name: githubName,
    size: buffer.length,
    digest: `sha256:${crypto.createHash('sha256').update(buffer).digest('hex')}`,
    url: latestAssetDownloadUrl(githubName),
  };
}

const manifest = {
  version,
  repository: REPOSITORY,
  releaseUrl: `https://github.com/${REPOSITORY}/releases/tag/v${version}`,
  assets: {
    arm64: assetEntry('arm64'),
    x64: assetEntry('x64'),
  },
};

const outputPath = path.join(releaseDirectory, LATEST_MANIFEST_ASSET_NAME);
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Created ${outputPath}`);
