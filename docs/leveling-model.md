# Leveling model

While leveling, an item's value is the change in **kills per hour** against a normal mob of your level, plus a
small share for survival. Code: `Model.LevelCycle` and `Model.Gain` in `Model.lua`; data: `Data/Leveling.lua`.

## The kill cycle

```
time per kill = fight + travel + rest + stops
fight  = mob health / your damage per second
rest   = soft max(health lost / food rate, mana spent / water rate)        (power-4 soft max)
         warlocks (Life Tap): max(health lost / food rate, (health lost + mana spent) / (food rate + water rate))
stops  = 3 s x (health lost / max health + mana spent / max mana)
gain   = (time per kill before / after) x (effective health after / before) ^ 0.05 - 1
```

- **health lost** = mob DPS x (1 - your armor reduction) x (1 - avoidance) x pet share x fight.
- **mana spent** = filler mana per second x share of the fight spent casting x fight, minus regeneration while
  fighting and while walking.
- **your damage per second** in absolute numbers comes from the part with a real size (auto attacks, auto shot or
  the filler spell) divided by its share of your damage (`Specs.lua`); physical damage goes through the mob's armor.

## Sources (WoW Forever game data unless noted)

| Input | Value | Source |
|---|---|---|
| Mob health, DPS before armor, armor, armor constant, levels 1-60 | e.g. level 35: 1586 HP, 28.26 DPS, 1387 armor, 3375 | `ExpectedStat` (ContentSetID 0), wago.tools build 1.60.1.71037 (2026-11-20). Level 60 row matches wowsims/forever `base_stats_auto_gen.go` |
| Armor reduction | armor / (armor + 400 + 85 x level) | `ExpectedStat.ArmorConstant` (same numbers) |
| Food and water per second by required level | e.g. level 35: 46.4 HP/s, 66.4 mana/s | ItemEffect + SpellEffect auras 84/85, wago.tools; same totals as Classic Era |
| Filler rank per level: base damage, mana, cast time, spell power coefficient | e.g. Shadow Bolt at 35: 84 dmg, 160 mana, 3.0 s, 0.857 | SpellLevels, SpellPower, SpellCastTimes, SpellEffect, wago.tools. Forever cut base damage of most fillers to 50-90 % of Classic Era (Shadow Bolt 84 vs 160 at 35) |
| Spirit mana regeneration | 6.25 + Spirit / 8 per second | wowsims/forever `sim/core/mana.go` (no level term); the game's own value is used when the client reports it |
| Combat table (miss, dodge, parry, glancing, crit suppression) | | wowsims/forever `sim/core/target.go` |

Raw tables and the generator: `ref/forever-data/` (`scripts/gen_leveling.py`).

## Estimates (no source found)

| Estimate | Value | Effect |
|---|---|---|
| Walking and pulling between mobs | 8 s | dilutes every gain the same way |
| Sitting down and getting up per rest | 3 s | the only reason a bigger health or mana pool helps in steady leveling |
| Survival share (deaths, bad pulls) | 5 % on effective health (20 % for tank specs, who pull several mobs) | stamina, armor and dodge get a little extra |
| Share of mob damage that reaches you with a pet tanking | 35 % (warlock, hunter; from level 10) | how much warlocks and hunters eat |
| Mana use of melee hybrids | 25-35 % of casting their reference spell nonstop | how much paladins, enhancement shamans and hunters drink |
| Share of your damage per part (white, specials, spell, pet, wand) | `Specs.lua` | splits damage between stats |

Known gaps: only the filler spell counts for casters (no DoTs, Moonfire or Mind Blast), so classes that live on
DoTs (Balance druids with Forever's weak Wrath, Affliction) get longer fights than in game. This changes how much
resting weighs against fighting, not which stat helps more. Spell availability follows the data: a level 1 Frost
mage uses Fireball until Frostbolt (level 4); priests heal with Lesser Heal, Heal or Greater Heal by level.

Community reports agree in direction (anecdotal, forums and guides): warriors eat after most pulls, warlocks and
hunters have the least downtime, mages drink most. The model gives, for example, rest per kill of 10 s for a
level 20 warrior (fight 21 s) and 6 s for a level 35 Demonology warlock (fight 24 s).

## What it means for stats while leveling

Example numbers from `tests/` characters (+10 of a stat on an empty slot):

| Character | +10 main stat | +10 Stamina | +10 Intellect | +10 Spirit | +100 Armor |
|---|---|---|---|---|---|
| Warlock 35 Demonology | +3.6 % (spell damage) | +0.45 % | +0.26 % | +0.21 % | |
| Paladin 25 Retribution | +2.9 % (Strength) | +0.77 % | +0.55 % | +0.30 % | +0.61 % |
| Warrior 20 Arms | +4.4 % (Strength) | +1.2 % | | | +1.2 % |

Stamina is worth much less than in fixed stat weights: at a steady pace you eat back what you lose, so a bigger
pool only saves sitting down and makes bad pulls survivable. Spell damage is worth a lot because Forever lowered
the base damage of caster spells, so each point of spell damage is a larger share of a cast.

Shadow priests from level 20 are modelled with Smite's damage, mana and cast time but Shadow school, since Mind
Flay is not in the generated spell table.
