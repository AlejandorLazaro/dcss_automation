-- Lua config file for Dungeon Crawl Stone Soup!
--
-- Features:
-- * A collection of dynamic build configuration Lua lists in `dcss_builds` supporting:
--   * Race and class checks for enabling a build
--   * Initial skill training target values (`skill_training`). E.g., "Fighting": 10
--   * Initial skill training intensity (`skill_start`). E.g., "Fighting" = * (meaning high intensity, or 2) compared to "+" being 1 or "-" for 0 or disabled from training
--   * Spell memorization list with conditions (`spell_mem_with_conditions`). E.g., Memorize "Summon Lightning Spire" when player is level 5+, has 4+ available spell levels, and has already memorized "Summon Blazeheart Golem"
--     * TODO: Consider requiring 1. certain success rate met  1. certain skill levels met
-- * Automatically memorize spells for builds that have spell configs after a certain amount of turns being safe.
-- Inspired by Sobeick's rcfile.lua present here: https://github.com/Sobieck/dcss-characters/blob/main/rcfile.lua

-- Version and other conditionally dependent variables

CONDITIONAL_SKILL_NAMES = {
    ["Ranged Weapons"] = (tonumber(crawl.version("major")) >= 0.29 and {"Ranged Weapons"} or {"Slings"})[1]
}

-- Constants

MIN_TURNS_FELT_SAFE_TO_MEM_SPELLS = 10  -- How long to wait before trying to automatically memorize spells
NUM_OF_PREV_MSGS_TO_PARSE = 5           -- Number of messages (by newline) to parse for logic checks in Lua functions (e.g.: Checking levelups, successful spell memorization, etc)
SPELL_MEM_DONE = "You finish memorizing"
SPELL_MEM_INT = "Your memorization is interrupted"
BAD_WELCOME = "Welcome back to the Dungeon!" -- This message is sent when coming back from Lair and other side branches
GOOD_WELCOME_EXISTING_SESSION = "Welcome back, "
GOOD_WELCOME_NEW_SESSION = "Welcome, "

-- Helper functions

function m_print(msg, color)
    if not color then color = "cyan" end
    crawl.mpr(string.format("<%s>%s</%s>", color, msg, color))
end

function underscores_to_spaces(msg)
    return msg:gsub("_", " ")
end

function spaces_to_underscores(msg)
    return msg:gsub(" ", "_")
end

function print_table(table, curr_depth, max_depth)
    if curr_depth==nil then curr_depth = 0 end
    if max_depth==nil then max_depth = 6 end
    if curr_depth==max_depth then
        m_print(string.format("%sTable goes deeper than max_depth value of %d. Stopping recursive table print.", string.rep(" ", 2*curr_depth), max_depth))
        return
    end
    if not table then
        m_print(string.format("%s[%s]:", string.rep(" ", 2*curr_depth), "nil"))
    else
        for k, v in pairs(table) do
            if type(v)=="table" then
                m_print(string.format("%s[%s]:", string.rep(" ", 2*curr_depth), tostring(k)))
                print_table(v, curr_depth + 1, max_depth)
            else
                m_print(string.format("%s[%s]: %s", string.rep(" ", 2*curr_depth), tostring(k), tostring(v)))
            end
        end
    end
end

function sanitize_skill_name(skill)
    u_to_s_skill = underscores_to_spaces(skill)
    return CONDITIONAL_SKILL_NAMES[u_to_s_skill] or u_to_s_skill
end

function does_meet_spell_mem_requirements(p_level, s_levels, known_spells)
    if p_level and you.xl() < p_level then return false end
    if s_levels and you.spell_levels() < s_levels then return false end
    if known_spells then
        for i=1, #known_spells do
            if not spells.memorised(known_spells[i]) then return false end
        end
    end
    return true
end

-- "Just did X" functions

level_up_message = "You have reached level "
level_up_message_w_number = level_up_message .. "%d+"
function just_leveled_up(message_buffer)
    local i, _ = message_buffer:find(level_up_message_w_number)
    if i then return true else return false end
end

function just_memorized_spell(message_buffer)
    local index_s, index_e = message_buffer:find("You finish memorizing")
    if index_s then
        m_print("Assuming latest spell learned was " .. you.spells()[#you.spells()])
        -- Eventually remove this spell from the list of spells to check in the 'curr_build'
        return true
    end
    return false
end

function just_started_new_game()
    if you.turns() == 0 then
        local i, _ = string.find(crawl.messages(NUM_OF_PREV_MSGS_TO_PARSE), GOOD_WELCOME_NEW_SESSION)
        if i then return true else return false end
    end
    return false
end

function just_started_game_session()
    local i, _ = string.find(crawl.messages(NUM_OF_PREV_MSGS_TO_PARSE), GOOD_WELCOME_EXISTING_SESSION)
    local j, _ = string.find(crawl.messages(NUM_OF_PREV_MSGS_TO_PARSE), GOOD_WELCOME_NEW_SESSION)
    if i or j then return true else return false end
    return false
end

-- BuildSpec class which controls all build configurations and functionality

BuildSpec = {}

function BuildSpec:new(config)
    has_spells = (config["spell_mem_with_conditions"] and {true} or {false})[1]
    newObj = {
        name = config["name"],
        condition = config["condition"],
        skill_training = config["skill_training"] or {},
        skill_start = config["skill_start"] or {},
        spell_mem_with_conditions = config["spell_mem_with_conditions"] or {},
        auto_mem_spells = has_spells
    }
    self.__index = self
    return setmetatable(newObj, self)
end

function BuildSpec:initialize_spell_sheet()
    self:set_starting_skill_intensity()
    self:set_starting_skill_training_targets()
end

function BuildSpec:set_starting_skill_training_targets()
    -- Set initial skill targets
    for skill_name, target in pairs(self.skill_training) do
        you.set_training_target(underscores_to_spaces(skill_name), target)
    end
end

function BuildSpec:set_starting_skill_intensity()
    -- Set training intensity of starting skills
    for skill_name, intensity in pairs(self.skill_start) do
        you.train_skill(underscores_to_spaces(skill_name), intensity)
    end
end

function BuildSpec:check_for_and_memorize_spells()
    -- TODO: Update this only once we memorize a new spell (and also remove based on Scrolls of Amnesia)
    local already_memorized_spells = {}
    for _, spell_name in pairs(you.spells()) do
        already_memorized_spells[spell_name] = true
    end

    -- TODO: Update this only once we read new spellbooks
    local spells_able_to_memorize = {}
    for _, spell_name in pairs(you.mem_spells()) do
        spells_able_to_memorize[spell_name] = true
    end

     -- k = "Spell Name", v = {"player_level" = 1, "spell_levels" = 1, ["skill_training" = ...]}
    for spell_name, spell_config in pairs(self.spell_mem_with_conditions) do
        -- Ignore spells that are already memorized or aren't in your spell books
        if spell_config and not already_memorized_spells[underscores_to_spaces(spell_name)] and spells_able_to_memorize[underscores_to_spaces(spell_name)] then
        -- elseif spell_config then
            local req = spell_config.conditions
            if does_meet_spell_mem_requirements(req["player_level"], req["spell_levels"], req["known_spells"]) then
                m_print(string.format("Currently feels safe and spell conditions have been met! Asking the user if they'd like to memorize the spell '%s'", underscores_to_spaces(spell_name)))
                crawl.more()
                if crawl.yesno(string.format("<lightgrey>Do you want to memorize</lightgrey> <white>'%s'</white> <lightgrey>at this time?<\lightgrey>", underscores_to_spaces(spell_name))) then
                    you.memorise(underscores_to_spaces(spell_name))
                    -- FIXME: Not training at the moment after memorizing
                    train_req = spell_config.skill_training
                    if train_req then
                        m_print("This spell has some skill training requirements! Updating skill training values!")
                        for i=1, #train_req do
                            you.train_skill(underscores_to_spaces(train_req[i]["skill"]), train_req[i]["intensity"])
                        end
                    end
                else
                    m_print(string.format("Not memorizing '%s' at this time...", underscores_to_spaces(spell_name)))
                end
            end
        end
    end

    -- Remove spells that are already memorized from future consideration
    -- This doesn't account for spells that get removed with a Scroll of Amnesia
    for spell_name, _ in pairs(already_memorized_spells) do
        -- m_print(string.format("Removing the spell '%s' from the list of spells-to-memorize...", underscores_to_spaces(newly_memorized_spells[i])))
        self.spell_mem_with_conditions[spaces_to_underscores(spell_name)] = nil
    end
end

function BuildSpec:print()
    m_print("Build name: " .. self.name)
    m_print(string.format("Activating condition: Race=%s && Class=%s", self.condition["race"], self.condition["class"]))
    if self.auto_mem_spells then
        m_print(string.format("Auto memorization for spells is ON for this build! After %d turns of feeling safe, you'll stop and try to memorize available spells meeting your build conditions!", MIN_TURNS_FELT_SAFE_TO_MEM_SPELLS))
    else
        m_print("No spells configured to auto-memorize for this build. Auto memorization for spells is OFF!")
    end
end

-- List of builds (activate/deactivate them with comments)

dcss_builds = {
    BuildSpec:new({
        name = "FeSumBuild",
        condition = {race = "Felid", class = "Summoner"},
        skill_training = {
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
        skill_start = {
            Spellcasting = 1,
            Summonings = 1
        },
        spell_mem_with_conditions = {
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
    }),
    BuildSpec:new({
        name = "CoMonBuild",
        condition = {race = "Coglin", class = "Monk"},
        skill_training = {
            Fighting = 10,
            Stealth = 10,
            Dodging = 10,
            Spellcasting = 14,
            Invocations = 11,
            Evocations = 5,
        },
        skill_start = {
            Fighting = 1,
            Short_Blades = 1,
            Dodging = 1,
            Stealth = 1
        }
    }),
    BuildSpec:new({
        name = "CoHunBuild",
        condition = {race = "Coglin", class = "Hunter"},
        skill_training = {
            Fighting = 10,
            Stealth = 10,
            Dodging = 10,
            Spellcasting = 14,
            Invocations = 11,
            Evocations = 5,
        },
        skill_start = {
            Fighting = 1,
            Ranged_Weapons = 1,
            Dodging = 1,
            Stealth = 1
        }
    })
}

-- Main body functions

-- When anything that ISN'T a wand a flame gets picked up, train Evo since it's a useful fallback
-- function picked_up_cool_wand_thing()
--     you.train_skill("Evocations", 2)

function untrain_all_skills()
	skill_list = {"Fighting","Short Blades","Long Blades","Axes","Maces & Flails",
                "Polearms","Staves","Unarmed Combat","Throwing","Ranged Weapons",
                "Armour","Dodging","Shields","Spellcasting",
                "Conjurations","Hexes","Charms","Summonings","Necromancy",
                "Translocations","Transmutations","Fire Magic","Ice Magic",
                "Air Magic","Earth Magic","Alchemy","Invocations",
                "Evocations","Stealth"}
	for i, sk in ipairs(skill_list) do
		you.train_skill(sk, 0)
	end
end

function manage_skills()
    m_print("Untraining all skills and letting default build skill management run...")
    untrain_all_skills()

    -- Skill configs by race and class
    curr_build:initialize_spell_sheet()
end

function determine_build()
    for build_name, build in pairs(dcss_builds) do
        if you.race() == build.condition.race and you.class() == build.condition.class then
            curr_build = build
            return
        end
    end
end

-- Main game loop function and updating variables

curr_build = nil
absolute_turns = 0
consecutive_turns_felt_safe = 0
waiting_to_memorize_spells = false

function ready()
    if just_started_game_session() then
        crawl.mpr(string.format("Hello <yellow>%s</yellow> and welcome to <cyan>DCSS with Lua helpers</cyan>!", you.name()))
        determine_build()
        waiting_to_memorize_spells = true  -- Just in case we have spells to memorize when we start the session
        absolute_turns = you.turns()
        consecutive_turns_felt_safe = 0

        -- Reset all values that the previous game may have set and set the proper skill targets
        if just_started_new_game() then
            waiting_to_memorize_spells = false

            if curr_build then
                curr_build:print()
                manage_skills()
            end
        end

        if not curr_build then
            m_print("No premade build config for your current race and class! This Lua helper will largely be disabled for this run.")
        end
    end

    if curr_build then
        -- Counter handling for 'safeness'. Useful to ensure we're in a good place before starting actions that could be dangerous otherwise (like memorizing spells in Zot:5)
        -- TODO: Interrupt 'o'-movement or other multi-actions to potentially memorize spells
        if you.feel_safe() then
            consecutive_turns_felt_safe = consecutive_turns_felt_safe + you.turns() - absolute_turns
        else
            consecutive_turns_felt_safe = 0
        end
        absolute_turns = you.turns()

        local message_buffer = crawl.messages(NUM_OF_PREV_MSGS_TO_PARSE)

        if consecutive_turns_felt_safe >= MIN_TURNS_FELT_SAFE_TO_MEM_SPELLS and waiting_to_memorize_spells then
            curr_build:check_for_and_memorize_spells()
            -- TODO: Move this to a check for if the spell we just attempted to memorize was done so successfully
            waiting_to_memorize_spells = false
        end

        -- if just_memorized_spell(message_buffer) then
        --     waiting_to_memorize_spells = false
        -- end

        if just_leveled_up(message_buffer) then
            -- Check to see if you can learn a new spell after levelling up
            if curr_build.auto_mem_spells then
                if #you.mem_spells() > 0 then
                    waiting_to_memorize_spells = true
                    if consecutive_turns_felt_safe < MIN_TURNS_FELT_SAFE_TO_MEM_SPELLS then
                        m_print("You leveled up and can learn a new spell, but it's not yet safe to do so!")
                    else
                        m_print("You leveled up and can learn a new spell! Checking the recommended memorization list...")
                        curr_build:check_for_and_memorize_spells()
                    end
                    m_print(string.format("NOTE: You have %d current spell levels available.", you.spell_levels()))
                end
            end
        end
        -- m_print("Turns felt safe: " .. consecutive_turns_felt_safe .. "; Waiting to mem new spells: " .. tostring(waiting_to_memorize_spells))
    end
end