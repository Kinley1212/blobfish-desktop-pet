const { validateConfig } = require('./config-store');
const {
  calculatePetMetrics,
  getMaxPetScale,
} = require('./pet-window-geometry');

function preparePetConfigForSave(input, characterSize, windowGeometry) {
  const validated = validateConfig(input);
  calculatePetMetrics(characterSize, validated.pet.scale, windowGeometry);
  return validated;
}

function repairLoadedPetConfig(input, characterSize, windowGeometry) {
  const validated = validateConfig(input);
  const maxScale = getMaxPetScale(characterSize, windowGeometry);

  try {
    calculatePetMetrics(characterSize, validated.pet.scale, windowGeometry);
    return Object.freeze({
      config: validated,
      changed: false,
      previousScale: validated.pet.scale,
      maxScale,
    });
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
  }

  const previousScale = validated.pet.scale;
  const repairedScale = Math.min(previousScale, maxScale);
  calculatePetMetrics(characterSize, repairedScale, windowGeometry);
  return Object.freeze({
    config: {
      ...validated,
      pet: { ...validated.pet, scale: repairedScale },
    },
    changed: repairedScale !== previousScale,
    previousScale,
    maxScale,
  });
}

function repairLoadedPetConfigWithFallback(input, character, fallbackCharacter, windowGeometry) {
  const validated = validateConfig(input);
  if (!character || typeof character.id !== 'string' || !character.size) {
    throw new TypeError('Loaded character descriptor is invalid');
  }
  if (!fallbackCharacter || typeof fallbackCharacter.id !== 'string' || !fallbackCharacter.size) {
    throw new TypeError('Fallback character descriptor is invalid');
  }

  try {
    const repaired = repairLoadedPetConfig(validated, character.size, windowGeometry);
    return Object.freeze({
      ...repaired,
      characterChanged: false,
      previousCharacterPackId: validated.pet.characterPackId,
      incompatibleCharacterPackId: null,
    });
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;

    const fallbackInput = {
      ...validated,
      pet: { ...validated.pet, characterPackId: fallbackCharacter.id },
    };
    const repaired = repairLoadedPetConfig(
      fallbackInput,
      fallbackCharacter.size,
      windowGeometry,
    );
    return Object.freeze({
      ...repaired,
      changed: true,
      characterChanged: validated.pet.characterPackId !== fallbackCharacter.id,
      previousCharacterPackId: validated.pet.characterPackId,
      incompatibleCharacterPackId: validated.pet.characterPackId,
    });
  }
}

module.exports = {
  preparePetConfigForSave,
  repairLoadedPetConfig,
  repairLoadedPetConfigWithFallback,
};
