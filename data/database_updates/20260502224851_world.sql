-- ==============================================
-- FILE: spell_affect.sql
-- GENERATED: 20260502224851
-- ==============================================
-- Throwing Weapon Specialization poison
REPLACE INTO spell_affect
(
    entry,
    effectId,
    SpellFamilyMask
)
VALUES
(13710, 1, 137438953472),
(13859, 1, 137438953472);

-- ==============================================
-- FILE: spell_effect_mod.sql
-- GENERATED: 20260502224851
-- ==============================================
-- Vigor
REPLACE INTO spell_effect_mod
(
    Id,
    EffectIndex,
    Effect,
    EffectDieSides,
    EffectBaseDice,
    EffectDicePerLevel,
    EffectRealPointsPerLevel,
    EffectBasePoints,
    EffectAmplitude,
    EffectPointsPerComboPoint,
    EffectChainTarget,
    EffectMultipleValue,
    EffectMechanic,
    EffectImplicitTargetA,
    EffectImplicitTargetB,
    EffectRadiusIndex,
    EffectApplyAuraName,
    EffectItemType,
    EffectMiscValue,
    EffectTriggerSpell,
    Comment
)
VALUES
(14983, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 42, -1, -1, -1, 'Vigor Rank 1: use proc trigger aura so spell_proc_event cooldown applies'),
(52527, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 42, -1, -1, -1, 'Vigor Rank 2: use proc trigger aura so spell_proc_event cooldown applies');

-- ==============================================
-- FILE: spell_mod.sql
-- GENERATED: 20260502224851
-- ==============================================
-- Vigor
REPLACE INTO spell_mod
(
    Id,
    AttributesEx3,
    Comment
)
VALUES
(14983, 67108864, 'Vigor Rank 1: poison proc'),
(52527, 67108864, 'Vigor Rank 2: poison proc');

-- ==============================================
-- FILE: spell_proc_event.sql
-- GENERATED: 20260502224851
-- ==============================================
-- Taste for Blood
REPLACE INTO spell_proc_event
(
    entry,
    SchoolMask,
    SpellFamilyName,
    SpellFamilyMask0,
    SpellFamilyMask1,
    SpellFamilyMask2,
    procFlags,
    procEx,
    ppmRate,
    CustomChance,
    Cooldown
)
VALUES
(14174, 0, 8, 1048576, 0, 0, 16, 524288, 0, 0, 0),
(14175, 0, 8, 1048576, 0, 0, 16, 524288, 0, 0, 0),
(14176, 0, 8, 1048576, 0, 0, 16, 524288, 0, 0, 0);

-- Vigor
REPLACE INTO spell_proc_event
(
    entry,
    SchoolMask,
    SpellFamilyName,
    SpellFamilyMask0,
    SpellFamilyMask1,
    SpellFamilyMask2,
    procFlags,
    procEx,
    ppmRate,
    CustomChance,
    Cooldown
)
VALUES
(14983, 0, 8, 268558336, 0, 0, 65536, 0, 0, 50, 8),
(52527, 0, 8, 268558336, 0, 0, 65536, 0, 0, 100, 8);

