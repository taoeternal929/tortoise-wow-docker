-- ==============================================
-- FILE: npc_trainer.sql
-- GENERATED: 20260430213501
-- ==============================================
-- Remove Deprecated Hemorrage Spell Ranks
DELETE FROM npc_trainer WHERE spell IN (6185, 13027, 17347, 17348);

-- Remove Deprecated Wound Poison Spell Ranks
DELETE FROM npc_trainer WHERE spell IN (13222, 13223, 13224, 13225, 13226, 13227, 13231, 13232,13233);

-- Add Ghostly Strike to Trainers
REPLACE INTO npc_trainer
(
    entry,
    spell,
    spellcost,
    reqskill,
    reqskillvalue,
    reqlevel
)
VALUES
(918, 14306, 4000, 0, 0, 20),
(1411, 14306, 4000, 0, 0, 20),
(3327, 14306, 4000, 0, 0, 20),
(3328, 14306, 4000, 0, 0, 20),
(3401, 14306, 4000, 0, 0, 20),
(3599, 14306, 4000, 0, 0, 20),
(4163, 14306, 4000, 0, 0, 20),
(4214, 14306, 4000, 0, 0, 20),
(4215, 14306, 4000, 0, 0, 20),
(4582, 14306, 4000, 0, 0, 20),
(4583, 14306, 4000, 0, 0, 20),
(4584, 14306, 4000, 0, 0, 20),
(5165, 14306, 4000, 0, 0, 20),
(5166, 14306, 4000, 0, 0, 20),
(5167, 14306, 4000, 0, 0, 20),
(13283, 14306, 4000, 0, 0, 20),
(80248, 14306, 4000, 0, 0, 20);

-- ==============================================
-- FILE: spell_effect_mod.sql
-- GENERATED: 20260430213501
-- ==============================================
-- Bloody Mess: remap the Hemorrhage bonus modifier to a spellmod op supported by this core.
REPLACE INTO `spell_effect_mod`
(
    `Id`,
    `EffectIndex`,
    `Effect`,
    `EffectDieSides`,
    `EffectBaseDice`,
    `EffectDicePerLevel`,
    `EffectRealPointsPerLevel`,
    `EffectBasePoints`,
    `EffectAmplitude`,
    `EffectPointsPerComboPoint`,
    `EffectChainTarget`,
    `EffectMultipleValue`,
    `EffectMechanic`,
    `EffectImplicitTargetA`,
    `EffectImplicitTargetB`,
    `EffectRadiusIndex`,
    `EffectApplyAuraName`,
    `EffectItemType`,
    `EffectMiscValue`,
    `EffectTriggerSpell`,
    `Comment`
)
VALUES
(51974, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 20, -1, 'Bloody Mess Rank 1: Hemorrhage aura bonus'),
(51975, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 20, -1, 'Bloody Mess Rank 2: Hemorrhage aura bonus');

-- ==============================================
-- FILE: spell_proc_event.sql
-- GENERATED: 20260430213501
-- ==============================================
-- Improved Ambush Energy Return Proc event
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
(14079, 0, 8, 8389120, 0, 0, 0, 1, 0, 0, 0),
(14080, 0, 8, 8389120, 0, 0, 0, 1, 0, 0, 0),
(14081, 0, 8, 8389120, 0, 0, 0, 1, 0, 0, 0);

-- Irritating Agent Proc event
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
(52535, 0, 8, 16777216, 0, 0, 4096, 524288, 0, 0, 0),
(52536, 0, 8, 16777216, 0, 0, 4096, 524288, 0, 0, 0),
(52537, 0, 8, 16777216, 0, 0, 4096, 524288, 0, 0, 0);

-- Blinding Haze Proc event
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
(51680, 0, 8, 4096, 0, 0, 65536, 0, 0, 0, 0),
(51681, 0, 8, 4096, 0, 0, 65536, 0, 0, 0, 0),
(51682, 0, 8, 4096, 0, 0, 65536, 0, 0, 0, 0);

