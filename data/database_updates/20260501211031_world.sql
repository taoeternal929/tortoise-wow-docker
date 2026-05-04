-- ==============================================
-- FILE: skill_line_ability.sql
-- GENERATED: 20260501211031
-- ==============================================
-- Add Rogues to class mask for 1 Handed Axes
UPDATE `skill_line_ability`
SET `class_mask` = 79
WHERE `id` = 248
  AND `skill_id` = 44
  AND `spell_id` = 196;

-- ==============================================
-- FILE: spell_affect.sql
-- GENERATED: 20260501211031
-- ==============================================
-- Blade Rush
REPLACE INTO spell_affect
(
    entry,
    effectId,
    SpellFamilyMask
)
VALUES
(52507, 0, 4294967296),
(52507, 1, 4294967296),
(52508, 0, 4294967296),
(52508, 1, 4294967296);

-- Aggression
-- Sinister Strike (0x2), Eviscerate (0x20000), Riposte (0x80000000), Surprise Attack (0x200000000)
REPLACE INTO spell_affect
(
    entry,
    effectId,
    SpellFamilyMask
)
VALUES
(18427, 0, 10737549314),
(18428, 0, 10737549314),
(18429, 0, 10737549314);

-- ==============================================
-- FILE: spell_learnspell.sql
-- GENERATED: 20260501211031
-- ==============================================
-- Additional Weapon skills for Weapon Expertise Rogue Talent
REPLACE INTO spell_learn_spell
(
    entry,
    SpellID,
    Active
)
VALUES
(30919, 52509, 0),
(30920, 52510, 0);

-- ==============================================
-- FILE: spell_proc_event.sql
-- GENERATED: 20260501211031
-- ==============================================
-- Honor Among Thieves proc event
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
(52512, 1, 0, 0, 0, 0, 69972, 2, 0, 0, 2),
(52514, 1, 0, 0, 0, 0, 69972, 2, 0, 0, 2);

