const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { localizeAccessoryName } = require('../src/core/ui-i18n');

const nativeRoot = path.join(__dirname, '..', 'native-appkit', 'Sources', 'BlobfishNative');
const delegate = fs.readFileSync(path.join(nativeRoot, 'AppDelegate.swift'), 'utf8');
const localization = fs.readFileSync(path.join(nativeRoot, 'NativeLocalization.swift'), 'utf8');

// Source contracts deliberately avoid starting NSApplication or showing any windows.
function method(name) {
  const start = delegate.indexOf(`func ${name}(`);
  assert.notEqual(start, -1, `Missing ${name}`);
  const rest = delegate.slice(start);
  const end = rest.slice(1).search(/\n    (?:@\w+\s+)*(?:private\s+)?func /u);
  return end < 0 ? rest : rest.slice(0, end + 1);
}

test('native menu static entries register both locales, including quick-timer presets', () => {
  const configure = method('configureStatusMenu');
  for (const name of [
    'settings', 'sendMessage', 'messages', 'fishStatus', 'clearStatus', 'chat', 'friendInteraction',
    'taskRoam', 'pause', 'performance', 'launch', 'locate', 'alertTitle', 'snooze', 'dismiss',
    'timerControl', 'timerPause', 'timerExtend', 'timerCancel', 'quickTimer', 'clocks', 'quit',
  ]) {
    assert.match(configure, new RegExp(`let ${name} = localizedMenuItem\\(`), name);
  }
  // Only enum-backed, dynamically refreshed items may bypass the static registry.
  const unregistered = [...configure.matchAll(/NSMenuItem\(\s*title:\s*([^\n]+)/gu)].map((match) => match[1]);
  assert.equal(unregistered.length, 2);
  assert.match(unregistered[0], /^status\.title\(isEnglish:/u);
  assert.match(unregistered[1], /^interaction\.title\(isEnglish:/u);
  assert.match(configure, /localizedMenuItem\(title, englishTitle, action: #selector\(startQuickTimer/u);
  assert.match(configure, /statusItem = item\s+syncQuickSettingsMenu\(\)/u);
  const register = method('localizedMenuItem');
  assert.match(register, /runtime\.config\.ui\.locale == "en" \? english : chinese/u);
  assert.match(register, /localizedMenuItems\.append\(\(item, chinese, english\)\)/u);
});

test('applying settings refreshes menu locale before restoring unread counts and timer labels', () => {
  assert.match(method('openSettings'), /self\.syncQuickSettingsMenu\(\)/u);
  const sync = method('syncQuickSettingsMenu');
  assert.match(sync, /for entry in localizedMenuItems/u);
  assert.match(sync, /entry\.item\.title = InterfaceLanguage\.authored\(english \? entry\.english : entry\.chinese, locale: runtime\.config\.ui\.locale\)/u);
  assert.match(sync, /updateMessengerMenu\(unreadCount: messengerMenuUnreadCount\)/u);
  assert.match(sync, /if let state = clockService\?\.state \{ updateClockMenu\(state\) \}/u);
  assert.ok(sync.indexOf('entry.item.title') < sync.indexOf('updateMessengerMenu('));
  assert.ok(sync.indexOf('entry.item.title') < sync.indexOf('updateClockMenu('));
  assert.doesNotMatch(sync, /messengerService\?\.unreadCount/u, 'Keep actor-isolated reads out of synchronous menu refresh');
  for (const item of ['pauseItem', 'taskRoamItem', 'performanceItem', 'launchAtLoginItem']) {
    assert.match(sync, new RegExp(`${item}\\?\\.state = runtime\\.config\\.`), item);
  }
});

test('language changes refresh both enum submenus without discarding their action identities', () => {
  const messenger = method('updateMessengerMenu');
  assert.match(messenger, /messengerMenuUnreadCount = unreadCount/u);
  assert.match(messenger, /unreadCount > 99 \? "99\+" : String\(unreadCount\)/u);
  assert.match(messenger, /for item in fishStatusMenuItem\?\.submenu\?\.items/u);
  assert.match(messenger, /FishUserStatus\(rawValue: raw\)/u);
  assert.match(messenger, /status\.title\(isEnglish: english\)/u);
  assert.match(messenger, /uiText\("清除状态", "Clear Status"\)/u);
  assert.match(messenger, /for item in friendInteractionMenuItem\?\.submenu\?\.items/u);
  assert.match(messenger, /FishRemoteInteraction\(rawValue: raw\)/u);
  assert.match(messenger, /interaction\.title\(isEnglish: english\)/u);
  assert.doesNotMatch(messenger, /removeAllItems|\.action\s*=|\.representedObject\s*=|\.state\s*=/u);
});

test('timer menu preserves user labels and translates running, paused and ringing controls', () => {
  const clock = method('updateClockMenu');
  assert.match(clock, /ringing\.label\.isEmpty \?/u);
  assert.match(clock, /timer\.state == "running"/u);
  for (const title of ['Time is up', 'Snooze 5 minutes', 'Dismiss', 'Timer', 'Pause timer', 'Resume timer', 'Add 5 minutes', 'Cancel timer']) {
    assert.ok(clock.includes(`"${title}"`), title);
  }
  assert.match(clock, /remainingTimerText\(\)/u);
  assert.doesNotMatch(clock, /startTimer|pauseTimer|resumeTimer|cancelTimer/u);
});

test('native and shared accessory exceptions match the named artwork rather than stale IDs', () => {
  const accessoryMethod = localization.split('static func accessoryName(')[1].split('static func shapeName(')[0];
  const names = [...accessoryMethod.matchAll(/"([a-z0-9-]+)": "([^"]+)"/gu)];
  assert.ok(names.length >= 20, 'Semantic exceptions must not silently revert to title-cased IDs');
  for (const [, id, name] of names) {
    assert.equal(localizeAccessoryName(id, '原始名称', 'en'), name, id);
    assert.equal(localizeAccessoryName(id, '原始名称', 'zh-CN'), '原始名称', id);
  }
  assert.equal(localizeAccessoryName('rilakkuma-cap-2', '', 'en'), 'Rilakkuma Baseball Cap (Style 2)');
  assert.equal(localizeAccessoryName('face-nosebleed', '', 'en'), 'Smitten');
  assert.equal(localizeAccessoryName('alarm-clock-plum-night', '', 'en'), 'Moonlight Jellyfish Clock');
});
