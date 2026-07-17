const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const architecture = process.argv[2] || process.arch;
if (!['arm64', 'x64'].includes(architecture)) {
  throw new Error(`Unsupported calendar helper architecture: ${architecture}`);
}

const targetArchitecture = architecture === 'x64' ? 'x86_64' : 'arm64';
const outputDirectory = path.join(root, 'native', 'build', architecture);
const outputPath = path.join(outputDirectory, 'blobfish-calendar-helper');
const sourcePath = path.join(root, 'native', 'CalendarHelper.swift');
const plistPath = path.join(root, 'native', 'CalendarHelper-Info.plist');
let sdkPath = process.env.BLOBFISH_SDK_PATH;
if (!sdkPath) {
  try {
    sdkPath = execFileSync('/usr/bin/xcrun', ['--sdk', 'macosx15.4', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  } catch {
    sdkPath = execFileSync('/usr/bin/xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  }
}

fs.mkdirSync(outputDirectory, { recursive: true });
execFileSync('/usr/bin/swiftc', [
  '-parse-as-library',
  '-O',
  '-sdk', sdkPath,
  '-module-cache-path', path.join(outputDirectory, 'module-cache'),
  '-target', `${targetArchitecture}-apple-macosx12.0`,
  '-framework', 'EventKit',
  '-Xlinker', '-sectcreate',
  '-Xlinker', '__TEXT',
  '-Xlinker', '__info_plist',
  '-Xlinker', plistPath,
  sourcePath,
  '-o', outputPath,
], { stdio: 'inherit' });
execFileSync('/usr/bin/codesign', ['--force', '--sign', '-', outputPath], { stdio: 'inherit' });
console.log(`Built ${outputPath}`);
