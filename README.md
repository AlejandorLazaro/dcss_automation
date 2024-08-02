# DCSS Automation

Scripts and other tools relating to [Dungeon Crawl Stone Soup](https://crawl.develz.org).

## Installation

### 1. macOS/Linux Application Download

1. Open the package contents of the application and copy the Lua files to the `settings` folder under `Resources`.
2. Copy the `dcssrc.lua` script from this repo to this location.
3. Edit the `init.txt` file and add the following line to the document: `lua_file = /dcssrc.lua`

Here's an example of the final path may look like:
`/Applications/Dungeon\ Crawl\ Stone\ Soup\ -\ Tiles.app/Contents/Resources/settings/dcssrc.lua`

### 2. Git clone of crawl

1. Open the top-level folder where you cloned the [crawl](https://github.com/crawl/crawl) project to.
2. Go to the subfolder path `crawl-ref/source`.
3. Copy the `dcssrc.lua` script from this repo to this location.

Here's an example of the final path may look like:
`~/GitHub/crawl/crawl-ref/source/dcssrc.lua`

**TODO:** Figure out how file aliases or init.txt file paths can reference the Lua file without needing the copy.

## Files and Features

#### dcssrc.lua
A Lua config file to automate skill training and spell memorization for user configured builds. This allows for builds that have manual skill targets and desired trainings to be more automated, preventing players from having to manually turn off and turn on skills at the start of a new game. (Inspired by Sobeick's [rcfile.lua](https://github.com/Sobieck/dcss-characters/blob/main/rcfile.lua))

**Features:**
* A collection of dynamic build configuration Lua lists in `dcss_builds` supporting:
  * Race and class checks for enabling a build
  * Initial skill training target values (`skill_training`). E.g., "Fighting": 10
  * Initial skill training intensity (`skill_start`). E.g., "Fighting" = * (meaning high intensity, or 2 in crawl code) compared to "+" being 1 or "-" for 0 or disabled from training
  * Spell memorization list with conditions (`spell_mem_with_conditions`).
    * E.g., Memorize "Summon Lightning Spire" when player is level 5+, has 4+ available spell levels, and has already memorized "Summon Blazeheart Golem"
    * **TODO:** Consider requiring 1. That certain success rate are met, and 2. That certain skill levels are met
* Automatically memorize spells for builds that have spell configs after a certain amount of turns being safe.

## Build Sample

Example build based on [Onei's Velvet-Pawed Path to Immortality - FeSu^Kiku/Jivya](http://crawl.chaosforge.org/Onei%27s_Velvet-Pawed_Path_to_Immortality_Walkthrough_-_FeSu%5EKikubaaqudgha/Jiyva):
```lua
dcss_builds = {
    -- ...other builds may be before or after this one
    BuildSpec:new({
        name = "Onei's Velvet-Pawed Path to Immortality",
        condition = {race = "Felid", class = "Summoner"},
        skill_training = { -- All other skills do not have starting training limits
            Fighting = 10,
            Stealth = 10,
            Dodging = 10,
            Spellcasting = 14,
            Summonings = 11,
            Fire_Magic = 5,
            Air_Magic = 5,
            Evocations = 5,
            Hexes = 8,
            Necromancy = 27
        },
        skill_start = { -- All other skills are disabled from training on character creation
            Spellcasting = 1,
            Summonings = 1
        },
        spell_mem_with_conditions = { -- The list of spells the player should try to learn whenever conditions are met, and the player has felt safe for a while
            Call_Imp = {
                conditions = {
                    player_level = 2, spell_levels = 2
                }
            },
            Call_Canine_Familiar = {
                conditions = {
                    player_level = 3, spell_levels = 3
                }
            },
            Summon_Blazeheart_Golem = {
                conditions = {
                    player_level = 4, spell_levels = 4
                },
                skill_training = {
                    {skill = "Fire Magic", intensity = 2}
                }
            },
            Summon_Lightning_Spire = {
                conditions = {
                    player_level = 5, spell_levels = 4,
                    known_spells = {
                        "Summon Blazeheart Golem"
                    }
                },
                skill_training = {
                    {skill = "Air Magic", intensity = 2},
                    {skill = "Fighting", intensity = 1},
                    {skill = "Dodging", intensity = 1},
                    {skill = "Stealth", intensity = 1}
                }
            },
            Anguish = {
                conditions = {
                    player_level = 4, spell_levels = 4
                },
                skill_training = {
                    {skill = "Necromancy", intensity = 2},
                    {skill = "Hexes", intensity = 2}
                }
            },
            Death_Channel = {
                conditions = {
                    player_level = 6, spell_levels = 6
                },
                skill_training = {
                    {skill = "Necromancy", intensity = 2}
                }
            }
        }
    })
```

## Development Notes

The Lua documentation for dcss at http://doc.dcss.io has stopped being updated since version 0.26, and therefore the best method to determine what Lua functions are available now is to clone the [crawl]() code directly and check the `l-<class name>.cc` files for up-to-date functionality.

E.g.: To see how you can get your current XL level, look up `xl` in files matching the pattern `l-*.cc`
```
-- Inside the file `l-you.cc`

/*** XL.
 * @treturn int xl
 * @tfunction xl
 */
LUARET1(you_xl, number, you.experience_level)

-- This resolves to `you.xl()` in Lua code
```