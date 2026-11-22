-- UI/InfoText.lua: the text of the "How scores work" page (written by Gemini Neon).
local _, GL = ...
GL.InfoText = {
	title = "How scores work",
	sections = {
		{
			heading = "What the number means",
			body = "Each item gets one percentage: how much stronger you get if you equip it instead of what you wear now.\n- Rings, trinkets, and one-handers check both slots and use the better gain.\n- Two-handers compare against your main hand and off hand together.",
		},
		{
			heading = "Leveling and raiding",
			body = "Switch modes at the top to match what you do.\n- Leveling (default below 60): mostly more kills per hour, plus a small share for staying alive on bad pulls.\n- Raiding (default at 60): damage on a raid boss three levels above you (or healing for healers), with a little survival and mana.",
		},
		{
			heading = "Kills per hour",
			body = "One kill adds fighting, walking (about 8 s), eating or drinking, and sitting down (about 3 s per stop).\n- Fight time: mob health divided by your damage per second.\n- Rest time: food for lost health or water for spent mana, whichever takes longer.\n- Warlocks Life Tap health into mana. Voidwalkers and hunter pets (from level 10) take hits for you.",
		},
		{
			heading = "Where numbers come from",
			body = "- Game data: WoW Forever mob health, damage, and armor (1 to 60), food, water, and your main spell.\n- Simulator: wowsims/forever combat rules (miss, dodge, glancing blows, crit, hit).\n- Character sheet: your stats, talents, and current gear.\n- Estimates: 8 s walking, 3 s sitting, pets taking 65% of hits, 5% survival share (20% for tanks), and hybrid mana use.",
		},
		{
			heading = "Reading the breakdown",
			body = "While leveling, three rows show Kills/hour, Survival, and \"Per kill\" seconds saved fighting and resting.\n- Each changed stat lists its share (like \"+14 Shadow Damage +2.9%\"), adding up to the total. Smaller stats group into \"Other stats\".\n- Weapon or shield changes get their own line.\n- Amber items marked \"Level 37\" need a higher level. Check before you buy, especially for an alt.",
		},
		{
			heading = "What is not counted",
			body = "- Use effects, procs (\"Chance on hit\"), and set bonuses.\n- Damage over time spells. Casters count only their main spell, so those classes may see longer fights.\nGood to know:\n- Stamina scores low while leveling. You eat back lost health anyway, so it mostly saves stops and helps on bad pulls.\n- Spell damage scores high because Blizzard lowered base spell damage.",
		},
	},
}
