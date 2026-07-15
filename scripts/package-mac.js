const { execFileSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { Arch, Platform, build } = require('electron-builder');

const root = path.join(__dirname, '..');
const architecture = process.argv[2];
if (process.platform !== 'darwin') {
  throw new Error('macOS packages must be built on macOS');
}
if (!['arm64', 'x64'].includes(architecture)) {
  throw new Error('Usage: node scripts/package-mac.js <arm64|x64>');
}

const archValue = architecture === 'arm64' ? Arch.arm64 : Arch.x64;
const outputDirectory = path.join(root, 'release', architecture);
const helperPath = path.join(root, 'native', 'build', architecture, 'blobfish-calendar-helper');
const iconPath = path.join(root, 'src', 'packs', 'characters', 'blobfish', 'art', 'character.svg');
const zipPath = path.join(root, 'release', `BlobfishDesktopPet-macOS-${architecture}.zip`);

function findAppBundle(directory) {
  const queue = [directory];
  while (queue.length > 0) {
    const current = queue.shift();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory() && entry.name.endsWith('.app')) return entryPath;
      if (entry.isDirectory()) queue.push(entryPath);
    }
  }
  throw new Error(`No app bundle found under ${directory}`);
}

function run(command, args, options = {}) {
  execFileSync(command, args, { cwd: root, stdio: 'inherit', ...options });
}

function deletePlistKey(plistPath, key) {
  const result = spawnSync('/usr/libexec/PlistBuddy', ['-c', `Delete :${key}`, plistPath], {
    encoding: 'utf8',
  });
  if (result.status !== 0 && !/Does Not Exist/.test(result.stderr)) {
    throw new Error(`Could not remove ${key} from ${plistPath}: ${result.stderr.trim()}`);
  }
}

async function main() {
  fs.mkdirSync(path.dirname(outputDirectory), { recursive: true });
  fs.rmSync(outputDirectory, { recursive: true, force: true });
  fs.rmSync(zipPath, { force: true });

  run(process.execPath, [path.join(__dirname, 'build-calendar-helper.js'), architecture]);

  await build({
    targets: Platform.MAC.createTarget('dir', archValue),
    config: {
      appId: 'com.blobfish.desktop-pet',
      productName: '水滴魚',
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
      extraResources: [{
        from: helperPath,
        to: 'native/blobfish-calendar-helper',
      }],
      mac: {
        category: 'public.app-category.productivity',
        icon: iconPath,
        identity: null,
        target: ['dir'],
      },
    },
  });

  const appPath = findAppBundle(outputDirectory);
  const bundledHelperPath = path.join(appPath, 'Contents', 'Resources', 'native', 'blobfish-calendar-helper');
  const infoPlistPath = path.join(appPath, 'Contents', 'Info.plist');
  for (const key of [
    'NSAppTransportSecurity',
    'NSAudioCaptureUsageDescription',
    'NSBluetoothAlwaysUsageDescription',
    'NSBluetoothPeripheralUsageDescription',
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
  ]) {
    deletePlistKey(infoPlistPath, key);
  }
  const executableName = execFileSync('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :CFBundleExecutable',
    infoPlistPath,
  ], { encoding: 'utf8' }).trim();
  const executablePath = path.join(appPath, 'Contents', 'MacOS', executableName);

  run('/usr/bin/codesign', ['--force', '--sign', '-', bundledHelperPath]);
  run('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', appPath]);
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', appPath]);

  const expectedMachine = architecture === 'arm64' ? 'arm64' : 'x86_64';
  for (const binaryPath of [executablePath, bundledHelperPath]) {
    const architectures = execFileSync('/usr/bin/lipo', ['-archs', binaryPath], { encoding: 'utf8' }).trim().split(/\s+/);
    if (architectures.length !== 1 || architectures[0] !== expectedMachine) {
      throw new Error(`Unexpected architecture for ${binaryPath}: ${architectures.join(' ')}`);
    }
    run('/usr/bin/file', [binaryPath]);
  }

  run('/usr/bin/ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', appPath, zipPath]);
  console.log(`Packaged ${appPath}`);
  console.log(`Created ${zipPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
