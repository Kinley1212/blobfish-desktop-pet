const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { ConfigStore, DEFAULT_CONFIG } = require('../src/core/config-store');
const {
  preparePetConfigForSave,
  repairLoadedPetConfig,
  repairLoadedPetConfigWithFallback,
} = require('../src/core/pet-config-geometry');
const {
  PET_BOTTOM_MARGIN,
  PET_SCALE_MIN,
  PET_WINDOW_HEIGHT,
  PET_WINDOW_WIDTH,
} = require('../src/core/pet-window-geometry');

const windowGeometry = {
  width: PET_WINDOW_WIDTH,
  height: PET_WINDOW_HEIGHT,
  bottomMargin: PET_BOTTOM_MARGIN,
};

test('save preflight rejects an oversized character before config storage is touched', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-pet-config-'));
  try {
    const store = new ConfigStore(directory);
    store.save(JSON.parse(JSON.stringify(DEFAULT_CONFIG)));
    const before = fs.readFileSync(store.filePath, 'utf8');
    const candidate = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
    candidate.pet.characterPackId = 'large-pet';
    candidate.pet.scale = 1.5;

    assert.throws(() => {
      const prepared = preparePetConfigForSave(
        candidate,
        { width: 512, height: 512 },
        windowGeometry,
      );
      store.save(prepared);
    }, /window width/);

    assert.equal(fs.readFileSync(store.filePath, 'utf8'), before);
    assert.deepEqual(store.get(), DEFAULT_CONFIG);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('the application persistence path performs geometry preflight before side effects', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/main.js'), 'utf8');
  const start = source.indexOf('function persistConfig(');
  const end = source.indexOf('\nfunction showPetContextMenu', start);
  const persistSource = source.slice(start, end);
  const preflightIndex = persistSource.indexOf('preparePetConfigForSave(');
  const loginItemIndex = persistSource.indexOf('syncLaunchAtLogin(');
  const diskWriteIndex = persistSource.indexOf('configStore.save(');

  assert.ok(start >= 0 && end > start);
  assert.ok(preflightIndex >= 0);
  assert.ok(loginItemIndex > preflightIndex);
  assert.ok(diskWriteIndex > preflightIndex);
});

test('startup repair falls back from a bubble-incompatible character without crashing', () => {
  const loaded = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  loaded.pet.characterPackId = 'large-pet';
  loaded.pet.scale = 1.5;

  const repaired = repairLoadedPetConfigWithFallback(
    loaded,
    { id: 'large-pet', size: { width: 512, height: 512 } },
    { id: 'blobfish', size: { width: 105, height: 90 } },
    windowGeometry,
  );

  assert.equal(repaired.changed, true);
  assert.equal(repaired.characterChanged, true);
  assert.equal(repaired.previousCharacterPackId, 'large-pet');
  assert.equal(repaired.previousScale, 1.5);
  assert.equal(repaired.maxScale, 1.5);
  assert.equal(repaired.config.pet.characterPackId, 'blobfish');
  assert.equal(repaired.config.pet.scale, 1.5);
  assert.equal(loaded.pet.characterPackId, 'large-pet', 'startup repair must not mutate the loaded object');
  assert.equal(loaded.pet.scale, 1.5, 'startup repair must not mutate the loaded object');
});

test('startup repair keeps a character when lowering its scale can satisfy the bubble contract', () => {
  const loaded = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  loaded.pet.characterPackId = 'tall-pet';
  loaded.pet.scale = 1.5;

  const repaired = repairLoadedPetConfigWithFallback(
    loaded,
    { id: 'tall-pet', size: { width: 200, height: 200 } },
    { id: 'blobfish', size: { width: 105, height: 90 } },
    windowGeometry,
  );

  assert.equal(repaired.changed, true);
  assert.equal(repaired.characterChanged, false);
  assert.equal(repaired.config.pet.characterPackId, 'tall-pet');
  assert.equal(repaired.config.pet.scale, 0.7);
});

test('startup repair leaves an already displayable configuration untouched', () => {
  const loaded = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  loaded.pet.characterPackId = 'wide-pet';
  loaded.pet.scale = PET_SCALE_MIN;

  const repaired = repairLoadedPetConfig(
    loaded,
    { width: 512, height: 32 },
    windowGeometry,
  );

  assert.equal(repaired.changed, false);
  assert.equal(repaired.config.pet.characterPackId, 'wide-pet');
  assert.equal(repaired.config.pet.scale, PET_SCALE_MIN);
});

test('a fallback startup configuration can be persisted and reloaded safely', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blobfish-pet-repair-'));
  try {
    const store = new ConfigStore(directory);
    const historical = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
    historical.pet.characterPackId = 'large-pet';
    historical.pet.scale = 1.5;
    // Older versions accepted this syntactically valid but undisplayable pair.
    store.save(historical);

    const repaired = repairLoadedPetConfigWithFallback(
      store.load(),
      { id: 'large-pet', size: { width: 512, height: 512 } },
      { id: 'blobfish', size: { width: 105, height: 90 } },
      windowGeometry,
    );
    store.save(repaired.config);

    const reloaded = new ConfigStore(directory).load();
    assert.equal(reloaded.pet.characterPackId, 'blobfish');
    assert.equal(reloaded.pet.scale, 1.5);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
