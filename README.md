# Upgrade Broker

![Upgrade Broker](docs/logo.png)

Gear upgrade addon for WoW Forever. It scans the Auction House and rates gear against what your character wears as one percentage in the upgrade window, bags, quest rewards, and item tooltips.

## Features

- Scans the Auction House with its own full scan or reads Auctionator's full scan, keeps the cheapest buyout per item variant, and lists the best upgrade per slot with price.
- Orders results by **Best value** or **Biggest upgrade**, with a **Max per item** price limit.
- Opens in an **Upgrades** tab inside the Auction House or anywhere with `/ub`. **Search Auction House** opens the item in the Auction House Buy view (addons cannot buy items on WoW Forever).
- Shows why an item is an upgrade: each changed stat with its share of the total, plus seconds per kill saved fighting and resting while leveling.
- Adds upgrade badges to gear in Blizzard bags and EllesmereUI Bags, marks quest rewards (frames the best usable choice, or puts a coin on the highest vendor value when nothing is an upgrade), and adds a rating line to item tooltips.
- Remembers every character you log in on (same realm and faction), so you can shop for alts from a bank character. Spec is detected from your talents.
- Shows gear a few levels ahead in amber with the level it needs.
- Skips gear the character cannot use: armor type (with an option for main armor type only), weapon skills, class restrictions, and professions (such as engineering goggles).
- Places settings in the EllesmereUI options panel when EllesmereUI is installed and follows EllesmereUI's theme.

## How scores work

Each item gets one percentage showing how much stronger the character gets.

- **Leveling:** Mostly more kills per hour from a kill cycle (fighting, walking, eating and drinking, sitting down) built on WoW Forever game data (mob health and damage per level, food and water, main spell ranks), plus a small share for survival.
- **Raiding:** Damage on a boss three levels above you, or healing for healers. Combat rules come from [wowsims/forever](https://github.com/wowsims/forever).
- **Not counted:** Use effects, procs, and set bonuses. Casters count only their main spell.

See [docs/leveling-model.md](docs/leveling-model.md) for the leveling math and data sources.

## Commands

- `/ub`: Open or close the upgrade window.
- `/ub item <link>`: Print the full rating for an item in chat.
- `/ub forget <name>`: Remove a remembered character.
- `/ub options`: Open settings.

## Development

### Tests

Run the unit and UI tests with Lua 5.1:

```sh
lua5.1 tests/run.lua
lua5.1 tests/ui.lua
```

### Data

`Data/Leveling.lua` is generated from WoW Forever CSV exports from [wago.tools](https://wago.tools):

```sh
python3 tools/gen_leveling.py <csv-folder> Data/Leveling.lua
```

### Releases

Push a version tag such as `v0.1.0`. GitHub Actions runs the tests and uses the BigWigs packager to upload the release to CurseForge, Wago, and GitHub.

## Credits

Combat rules and class constants follow [wowsims/forever](https://github.com/wowsims/forever) (MIT).

## License

MIT
