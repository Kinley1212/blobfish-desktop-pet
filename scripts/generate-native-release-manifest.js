const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const REPOSITORY = 'Kinley1212/blobfish-desktop-pet';
const root = path.join(__dirname, '..');
const releaseDirectory = path.join(root, 'release');
const infoPlistPath = path.join(root, 'native-appkit', 'App', 'Info.plist');
const infoPlist = fs.readFileSync(infoPlistPath, 'utf8');
const versionMatch = infoPlist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/);

if (!versionMatch || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(versionMatch[1])) {
  throw new Error('Native CFBundleShortVersionString is missing or invalid');
}

const version = versionMatch[1];
const architectures = process.argv.slice(2);

if (architectures.length === 0
    || new Set(architectures).size !== architectures.length
    || architectures.some((architecture) => !['arm64', 'x64'].includes(architecture))) {
  throw new Error('Usage: node scripts/generate-native-release-manifest.js <arm64|x64> [...]');
}

function assetEntry(architecture) {
  const name = `BlobfishNative-${version}-macOS-${architecture}.zip`;
  const localPath = path.join(releaseDirectory, name);
  const buffer = fs.readFileSync(localPath);
  return {
    name,
    size: buffer.length,
    digest: `sha256:${crypto.createHash('sha256').update(buffer).digest('hex')}`,
    url: `https://github.com/${REPOSITORY}/releases/download/v${version}/${name}`,
  };
}

const manifest = {
  channel: 'native-appkit',
  version,
  repository: REPOSITORY,
  assets: Object.fromEntries(architectures.map((architecture) => [architecture, assetEntry(architecture)])),
};

const outputPath = path.join(releaseDirectory, 'blobfish-native-latest.json');
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Created ${outputPath}`);
