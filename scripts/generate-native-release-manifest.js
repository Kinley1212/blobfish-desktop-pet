const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const REPOSITORY = 'Kinley1212/blobfish-desktop-pet';
const root = path.join(__dirname, '..');
const releaseDirectory = path.join(root, 'release');
const infoPlistPath = path.join(root, 'native-appkit', 'App', 'Info.plist');
const infoPlist = fs.readFileSync(infoPlistPath, 'utf8');
const versionMatch = infoPlist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/);

if (!versionMatch || !/^\d+\.\d+\.\d+$/.test(versionMatch[1])) {
  throw new Error('Native CFBundleShortVersionString is missing or invalid');
}

const version = versionMatch[1];

function assetEntry(architecture) {
  const name = `BlobfishNative-${version}-macOS-${architecture}.zip`;
  const localPath = path.join(releaseDirectory, name);
  const buffer = fs.readFileSync(localPath);
  return {
    name,
    size: buffer.length,
    digest: `sha256:${crypto.createHash('sha256').update(buffer).digest('hex')}`,
    url: `https://github.com/${REPOSITORY}/releases/latest/download/${name}`,
  };
}

const manifest = {
  channel: 'native-appkit',
  version,
  repository: REPOSITORY,
  assets: {
    arm64: assetEntry('arm64'),
    x64: assetEntry('x64'),
  },
};

const outputPath = path.join(releaseDirectory, 'blobfish-native-latest.json');
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Created ${outputPath}`);
