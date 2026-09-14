const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..', 'native-appkit', 'Sources', 'BlobfishNative');
const read = name => fs.readFileSync(path.join(root, name + '.swift'), 'utf8');
const service = read('FishMessengerService');
const panel = read('PetPanelController');
const delegate = read('AppDelegate');

test('relay upload starts a pending call without activating the visitor', () => {
  const send = service.slice(service.indexOf('func send('), service.indexOf('private func setPendingVisit'));
  assert.ok(send.indexOf('setPendingVisit(FishPendingVisit(') < send.indexOf('try await relay.deliver('));
  assert.match(send, /guard pendingVisit == nil, activeVisitContactID == nil/);
  assert.match(send, /activeVisitContactID = \(kind == \.visitStart \|\| kind == \.visitAccept\) \? activeVisitContactID/);
  assert.match(send, /if pendingVisit\?\.requestID == message.id \{ setPendingVisit\(nil\) \}/);
});

test('incoming acceptance is correlated before changing presence and active state', () => {
  const poll = service.slice(service.indexOf('func poll()'));
  assert.ok(poll.indexOf('pendingVisit?.accepts(') < poll.indexOf('let nextActiveContactID'));
  assert.match(poll, /replyTo: message.replyTo/);
  assert.match(poll, /FishPendingVisit.invitationIsFresh/);
  assert.match(delegate, /replyTo: message.id, kind: \.visitAccept/);
  assert.match(poll, /setPendingVisit\(previousPendingVisit\)/);
  assert.match(poll, /activeVisitLastSeenAt = previousVisitLastSeenAt/);
});

test('pending call cleanup covers timeout, cancellation, settings and shutdown', () => {
  assert.match(service, /kind == \.visitEnd, pendingVisit\?\.contactID == contactID \{\s*setPendingVisit\(nil\)/);
  assert.match(service, /if !value.visitsEnabled \{\s*setPendingVisit\(nil\)/);
  assert.match(service, /func stop\(\) \{\s*setPendingVisit\(nil\)/);
  assert.match(service, /activeVisitContactID \?\? pendingVisit\?\.contactID/);
  assert.match(service, /pendingVisitTimer\?\.invalidate\(\)/);
  assert.match(service, /pendingVisit\?\.requestID == value.requestID/);
  assert.match(delegate, /setVisitCalling\(messenger.pendingVisit != nil\)/);
});

test('arrival reuses the movement display link and cleans up without changing fling velocity', () => {
  const arrival = panel.slice(panel.indexOf('private func finishVisitArrival'), panel.indexOf('func showVisit'));
  assert.doesNotMatch(arrival, /Timer\(|asyncAfter|flingVelocity|setFrameOrigin/);
  assert.match(arrival, /accessibilityDisplayShouldReduceMotion/);
  assert.match(panel, /func moveOneFrame\(\) \{\s*updateVisitArrival\(/);
  assert.match(panel, /positioned: \.below, relativeTo: guestView/);
  assert.match(panel, /func endVisit\(\)[\s\S]*?finishVisitArrival\(\)/);
  const view = read('PetView');
  assert.match(view, /artworkLayer.opacity = Float\(arrivalProgress\)/);
  assert.match(view, /var visitCalling = false/);
});
