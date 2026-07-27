const fs = require('fs');
const path = require('path');
const { Arch, Platform, build } = require('electron-builder');
const packageManifest = require('../package.json');

const root = path.join(__dirname, '..');
const productName = `水滴鱼Pro${packageManifest.version}`;
const architecture = process.argv[2] || 'x64';

if (!['x64'].includes(architecture)) {
  throw new Error('Usage: node scripts/package-win.js <x64>');
}

const archValue = Arch.x64;
const outputDirectory = path.join(root, 'release', `win-${architecture}`);
const zipPath = path.join(root, 'release', `${productName}-windows-${architecture}.zip`);

async function main() {
  fs.mkdirSync(path.dirname(outputDirectory), { recursive: true });
  fs.rmSync(outputDirectory, { recursive: true, force: true });
  fs.rmSync(zipPath, { force: true });

  await build({
    targets: Platform.WINDOWS.createTarget('zip', archValue),
    config: {
      appId: 'com.blobfish.desktop-pet',
      productName,
      electronVersion: '43.1.1',
      asar: true,
      npmRebuild: false,
      directories: {
        output: outputDirectory,
      },
      files: [
        'src/**/*',
        'package.json',
      ],
      win: {
        target: ['zip'],
        artifactName: `${productName}-windows-${architecture}.${'${ext}'}`,
      },
    },
  });

  const packagedZip = path.join(outputDirectory, `${productName}-windows-${architecture}.zip`);
  if (!fs.existsSync(packagedZip)) {
    throw new Error(`Windows zip was not created at ${packagedZip}`);
  }
  fs.renameSync(packagedZip, zipPath);
  console.log(`Created ${zipPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
