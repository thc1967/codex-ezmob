local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- @class EZMobMonsterParser : EZMobTextLineParser
--- @field name string The name of the monster being parsed
--- @field monster table An internal representation of the parsed monster
--- @field importOptions table Optional configuration passed in via import context.
--- @field isImportable boolean Whether the monster passed validation and can be imported.
--- Base class for parsing monster entries from text into structured monster tables.
--- Provides common functionality shared between different monster format parsers.
EZMobMonsterParser = RegisterGameType("EZMobMonsterParser", "EZMobTextLineParser")
EZMobMonsterParser.__index = EZMobMonsterParser

--- Creates a new parser for the given entry.
--- @param entry table A table containing `name` and `text` (array of strings).
--- @return table|nil instance The instance of the parser
function EZMobMonsterParser:new(entry)
    if not entry then return end
    local instance = setmetatable(EZMobTextLineParser:new(entry.text), self)
    instance.name = entry.name
    instance.monster = {}
    instance.importOptions = import.options or {}
    instance.isImportable = true
    return instance
end

--- Static function to find and extract monster blocks from text.
--- Searches for monster headers and groups associated text lines into structured entries.
--- @param text string The full input text to parse.
--- @param headerPattern string The regex pattern indicating the first line of a new monster.
--- @return table monsters An array of monster objects, each with a `name` and `text` array.
function EZMobMonsterParser.FindMonsters(text, headerPattern)
    local monsters = {}
    local current = nil

    -- Normalize and split text into lines
    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Match Monster headers in the lines and accumulate into blocks
    for _, line in ipairs(lines) do
        local monsterMatch = regex.MatchGroups(line, headerPattern)
        local monsterName = monsterMatch and monsterMatch.name

        if monsterName and #monsterName > 0 then
            writeDebug("FOUND MONSTER [%s]", monsterName)
            current = {
                name = EZMobUtils.toTitleCase(monsterName),
                text = { line }
            }
            table.insert(monsters, current)
        elseif current then
            table.insert(current.text, line)
        end
    end

    return monsters
end

--- Returns the parsed monster table.
--- Used after parsing to retrieve the full monster structure built by the parser.
--- @return table monster The parsed monster table.
function EZMobMonsterParser:GetMonster()
    return self.monster
end

--- Orchestrates the full parsing process for a monster entry.
--- Calls header and body parsing methods, logs progress, and returns importability status.
--- @return boolean importable `true` if the monster was successfully parsed and marked importable; `false` otherwise.
function EZMobMonsterParser:Parse()
    writeLog(string.format("Parsing monster [%s] starting.", self.name), EZMobUtils.STATUS.INFO, 1)

    self.monster.name = self.name
    self:_parseHeader()
    self:_parseBody()

    writeDebug("MONSTERPARSER PARSE COMPLETE [%s] importable [%s] %s", self.name, self.isImportable, json(self.monster))
    writeLog(string.format("Parsing monster [%s] complete.", self.name), EZMobUtils.STATUS.INFO, -1)

    return self.isImportable
end

--- Static function to parse a single monster entry into a structured monster object.
--- Creates a parser instance, attempts to parse the entry, and returns the results.
--- @param parserClass table The parser class to instantiate (e.g., EZMobMonsterParserRetail).
--- @param entry table A monster entry containing `name` and `text` fields.
--- @return table|nil monster The parsed monster object on success, or nil on failure.
--- @return table|nil source The source information object on success, or nil on failure.
function EZMobMonsterParser.ParseMonster(parserClass, entry)
    local parser = parserClass:new(entry)
    if parser and parser:Parse() then
        return parser:GetMonster(), parser:GetSource()
    end
    return nil, nil
end

--- Extracts a characteristic being tested from text using regex, mapping to 3-letter abbreviation.
--- @param text string The full input text to search.
--- @return string|nil attribute The 3-letter abbreviation of the matched characteristic, or nil if not found.
function EZMobMonsterParser._extractRRAttribute(text)
    if not text or #text == 0 then return nil end

    local match = regex.MatchGroups(text, EZMobConfig.regex.monster.legacy.body.ability.rrAttribute)
    if not match or not match.stat then return nil end

    local rawStat = match.stat:lower()
    local map = {
        might = "mgt", mgt = "mgt", m = "mgt",
        agility = "agl", agi = "agl", a = "agl",
        reason = "rea", rea = "rea", r = "rea",
        intuition = "inu", inu = "inu", i = "inu",
        presence = "prs", prs = "prs", p = "prs"
    }

    return map[rawStat]
end

--- Maps parsed characteristic values directly into attribute tables with baseValue entries.
--- Assumes `match` is valid and contains all required characteristic keys.
---
--- @private
--- @param match table A table of parsed characteristic values keyed by attribute short name.
--- @return table<string, table> result A table mapping each attribute to a table with `baseValue`.
function EZMobMonsterParser:_mapCharacteristics(match)
    local result = {}
    for _, key in ipairs(EZMobConfig.validations.monster.characteristics) do
        result[key] = { baseValue = tonumber(match[key]) }
    end
    return result
end

--- Converts the monster's moveTypes string into a keyed table where each movement type
--- is a key and the monster's speed is the value.
---
--- Handles a string that may be empty, a single value, or comma-separated values.
---
--- @private
--- @param moveTypes string A comma-separated list of movement types
--- @return table<string, number> map A table mapping each movement type to the monster's speed.
function EZMobMonsterParser:_mapMoveSpeeds(moveTypes)
    local map = {}
    local speed = self.monster.speed or 0
    moveTypes = moveTypes or ""

    for move in moveTypes:gmatch("[^,%s]+") do
        map[move] = speed
    end

    return map
end

--- Parses a feature block from the monster entry.
--- Accumulates multiline feature text into `f.description` until a blank line
--- or a recognizable header/ability/feature pattern is encountered.
--- Applies name and formatting cleanup after parsing.
--- @param f table The feature object being populated.
--- @param enders table The list of regex entries that ends a feature
function EZMobMonsterParser:_parseFeature(f, enders)
    writeLog(string.format("Parse Feature [%s] starting.", f.name), EZMobUtils.STATUS.INFO, 1)

    local endOfFeature = false
    while not self.eof and not endOfFeature do
        local sLine = self:_getNextLine()

        -- Blank lines end features
        if sLine == "" then break end

        -- If we find a match on the parses, we need to put the
        -- line back and conclude our Feature
        for _, pattern in ipairs(enders) do
            local match = regex.MatchGroups(sLine, pattern)
            if match then
                self:_putLine()
                endOfFeature = true
                break
            end
        end

        -- Support for multiline feature text - add the text to the description.
        if not endOfFeature then
            if #f.description > 0 and not f.description:match("%s$") then
                f.description = f.description .. " "
            end
            f.description = f.description .. sLine
        end
    end

    writeLog(string.format("Parse Feature [%s] complete.", f.name), EZMobUtils.STATUS.INFO, -1)
end

--- Parses and applies damage type immunities or weaknesses directly to the monster.
--- Logs a warning if a damage type is not recognized by the system.
--- @param raw string Comma-separated values like "acid 2, fire 3"
--- @param multiplier number Value multiplier (e.g., 1 for immunity, -1 for weakness)
function EZMobMonsterParser:_parseImmunities(raw, multiplier)
    if not raw or raw == "" or #tostring(raw) < 3 then return end

    for entry in raw:gmatch("[^,]+") do
        local t, v = entry:match("^%s*(%a+)%s+(%-?%d+)%s*$")
        if t and v then
            local damageType = "all"
            local keywords = nil
            local di = import:GetExistingItem(DamageType.tableName, t)
            if di then
                damageType = di.name:lower()
            else
                keywords = { [t] = true }
            end

            local r = self.monster.resistances or  {}
            r[#r + 1] = ResistanceEntry.new {
                keywords = keywords,
                damageType = damageType,
                apply = "Damage Reduction",
                dr = tonumber(v) * multiplier,
            }

            self.monster.resistances = r
        end
    end
end

--- Validates a size value against supported creature sizes.
--- Compares the passed size to entries in `dmhub.rules.CreatureSizes` (case-insensitive).
--- @private
--- @param size string The size value to test
--- @return string|nil size The valid size name if found, or nil if not supported.
function EZMobMonsterParser:_validSize(size)
    if size == nil or #size == 0 then return nil end
    for _,e in ipairs(dmhub.rules.CreatureSizes) do
        if string.lower(e.name) == string.lower(size) then
            return e.name
        end
    end
    return nil
end

--- Validates an ability object to determine if it contains sufficient and correct data for import.
--- Checks for presence and length of `name` and `action` fields, and validates roll structure if present.
--- For power-based rolls, ensures that all three roll tiers are defined.
--- Sets `a.isImportable` to `true` or `false` based on the validation outcome.
--- Logs warnings for any detected issues.
--- @param a table The ability object to validate and annotate.
--- @return boolean importable `true` if the ability is valid and importable, `false` otherwise.
function EZMobMonsterParser._validateAbility(a)
    a.isImportable = true

    if type(a.name) ~= "string" or #a.name == 0 then
        a.isImportable = false
        writeLog("!!!! Invalid Ability - Name not found.", EZMobUtils.STATUS.WARN)
    end

    if type(a.action) ~= "string" or #a.action == 0 then
        a.isImportable = false
        writeLog(string.format("!!!! Invalid Ability [%s] - No Action.", a.name))
    end

    EZMobMonsterParser._validateAbilityTargetDistance(a)
    writeDebug("DISTANCETARGET:: 11 a.targetDistance %s", json(a.targetDistance))

    if a.roll then
        if type(a.roll.roll) == "string" and #a.roll.roll > 0 then
            a.roll.type = "power"
        else
            a.roll.type = ""
            local rrAttr = EZMobMonsterParser._extractRRAttribute(a.effect)
            if rrAttr and #rrAttr > 0 then
                a.roll.type = "resist"
                a.roll.resistAttr = rrAttr
                writeDebug("RESISTROLL:: validate [%s] [%s]", a.name, rrAttr)
            else
                a.isImportable = false
                writeLog(string.format("!!!! Invalid Ability [%s] - Roll resistance without attribute.", a.name), EZMobUtils.STATUS.WARN)
                writeDebug("PARSEABILITY BADRR effect [%s]", a.effect)
            end
        end

        local rt = a.roll.rollTable
        if type(rt) ~= "table" then
            a.isImportable = false
            writeLog(string.format("!!!! Invalid Ability [%s] - Has Roll but no Roll Table.", a.name), EZMobUtils.STATUS.WARN)
        else
            if type(rt.rollTier1) ~= "string" or #rt.rollTier1 == 0 then
                a.isImportable = false
                writeLog(string.format("!!!! Invalid Ability [%s] - Roll Table missing Tier 1.", a.name), EZMobUtils.STATUS.WARN)
            end
            if type(rt.rollTier2) ~= "string" or #rt.rollTier2 == 0 then
                a.isImportable = false
                writeLog(string.format("!!!! Invalid Ability [%s] - Roll Table missing Tier 2.", a.name), EZMobUtils.STATUS.WARN)
            end
            if type(rt.rollTier3) ~= "string" or #rt.rollTier3 == 0 then
                a.isImportable = false
                writeLog(string.format("!!!! Invalid Ability [%s] - Roll Table missing Tier 3.", a.name), EZMobUtils.STATUS.WARN)
            end
        end
    end
    writeDebug("DISTANCETARGET:: 12 a.targetDistance %s", json(a.targetDistance))

    return a.isImportable
end

--- Validates and parses the distance and target values from an ability object.
--- 
--- This function normalizes and interprets an ability's distance and target fields, including:
--- - Setting defaults if either field is missing
--- - Normalizing distance formats and range values
--- - Identifying special range types like cube, line, or burst
--- - Converting target phrases to structured data like targetType, range, numTargets, and targetFilter
--- - Logs warnings for unrecognized formats
---
--- The results are saved into a new table `targetDistance` within the passed-in ability object (`aP`).
---
--- @param aP table The parsed ability data to validate and enrich.
function EZMobMonsterParser._validateAbilityTargetDistance(aP)
    local cfgVals = EZMobConfig.regex.monster.validations
    local aI = {}

    writeLog("Parsing Ability Distance and Target starting.", EZMobUtils.STATUS.INFO, 1)
    writeDebug("DISTANCETARGET:: 0 [%s]", aP.name)

    if not aP.target or #aP.target == 0 then
        writeLog("!!!! Target missing from import. Using default.", EZMobUtils.STATUS.WARN)
        aP.target = "1 creature or object"
    end

    if not aP.distance or  #aP.distance == 0 then
        writeLog("!!!! Distance missing from import. Using default.", EZMobUtils.STATUS.WARN)
        aP.distance = "1"
    else
        local distanceMatch = regex.MatchGroups(aP.distance, cfgVals.distanceRange)
        if distanceMatch ~= nil then
            writeLog(string.format("Distance: parsed from [%s] to [%s].", aP.distance, distanceMatch.range))
            aP.distance = distanceMatch.range
        end
    end
    writeDebug("DISTANCETARGET:: 1 aP.distance=[%s]", aP.distance)

    -- Workaround for triggers
    if type(aP.target) == "string" and aP.target:lower():find("triggering creature") then
        aP.target = "1 creature"
    end

    local numbersTable = { ["a"] = 1, ["an"] = 1, ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8, ["nine"] = 9, ["ten"] = 10, }
    local numberedTargetsMatch = regex.MatchGroups(aP.target, cfgVals.numberedTargetsMatch)
    if numberedTargetsMatch ~= nil then
        aP.range = string.match(aP.distance, "%d+")
        if aP.range == nil then
            writeLog(string.format("!!!! Unrecognized target distance [%s]", aP.distance), EZMobUtils.STATUS.WARN)
            aP.range = 1
        end
        aP.range = tonumber(aP.range)
        writeDebug("DISTANCETARGET:: 2 aP.range=[%s]", aP.range)

        local meleeOrRangedMatch = regex.MatchGroups(aP.distance, cfgVals.meleeOrRangedMatch)
        if meleeOrRangedMatch ~= nil then
            aP.range = tonumber(meleeOrRangedMatch.ranged)
            aI.meleeRange = tonumber(meleeOrRangedMatch.melee)
        end
        writeDebug("DISTANCETARGET:: 3 aP.range=[%s]", aP.range)

        aI.targetType = "target"
        aI.numTargets = numbersTable[string.lower(numberedTargetsMatch.number)] or tonumber(numberedTargetsMatch.number)
        aI.range = aP.range
        writeDebug("DISTANCETARGET:: 4 aI.range=[%s]", aI.range)

        local lcType = (numberedTargetsMatch.type or ""):lower()
        if lcType == "enemy" or lcType == "enemies" then
            aI.targetFilter = "Enemy"
        elseif lcType == "ally" or lcType == "allies" then
            aI.targetFilter = "not Enemy"
        end
    elseif EZMobConfig.validations.monster.targetsForRangeCheck[aP.target:lower()] then
        local _,flatRange = regex.Match(aP.distance, cfgVals.flatRangeCheck)
        if flatRange ~= nil then
            aI.targetType = "all"
            aI.range = tonumber(flatRange)
            aI.numTargets = 1
            writeDebug("DISTANCETARGET:: 5 aI.range=[%s]", aI.range)
        else
            local cubeMatch = regex.MatchGroups(aP.distance, cfgVals.cubeRangeCheck)
            if cubeMatch ~= nil then
                aI.targetType = "cube"
                aI.numTargets = "1"
                aI.radius = tonumber(cubeMatch.radius)
                aI.range = tonumber(cubeMatch.range)
                writeDebug("DISTANCETARGET:: 6 aI.range=[%s], aI.radius=[%s]", aI.range, aI.radius)
            else
                local lineMatch = regex.MatchGroups(aP.distance, cfgVals.lineMatchCheck)
                if lineMatch ~= nil then
                    if tonumber(lineMatch.range) ~= 1 then
                        writeLog("!!!! Do not currently support line abilities with range other than 1.", EZMobUtils.STATUS.WARN)
                        lineMatch.range = 1
                    end
                    aI.targetType = "line"
                    aI.numTargets = 1
                    aI.radius = tonumber(lineMatch.width)
                    aI.range = tonumber(lineMatch.length)
                    writeDebug("DISTANCETARGET:: 7 aI.range=[%s]", aI.range)
                else
                    local burstMatch = regex.MatchGroups(aP.distance, cfgVals.burstMatchCheck)
                    if burstMatch ~= nil then
                        aI.targetType = "all"
                        aI.range = tonumber(burstMatch.radius)
                        aI.numTargets = 1
                        writeDebug("DISTANCETARGET:: 8 aI.range=[%s]", aI.range)
                    else
                        writeLog(string.format("!!!! Unrecognized target distance [%s] with target [%s].", aP.distance, aP.target), EZMobUtils.STATUS.WARN)
                    end
                end
            end
        end
        writeDebug("DISTANCETARGET:: 9 aI.range=[%s]", aI.range)

        local lcTarget = aP.target:lower()
        if string.find(lcTarget, "allies") ~= nil then
            aI.targetFilter = "not Enemy"
        elseif string.find(lcTarget, "enem") ~= nil then
            aI.targetFilter = "Enemy"
        elseif lcTarget == "each ally" or lcTarget == "all allies" then
            aI.targetFilter = "not Enemy"
        elseif lcTarget == "self and each ally" then
            aI.targetFilter = "not Enemy"
            aI.selfTarget = true
        end
    elseif not EZMobConfig.validations.monster.targetsForIgnoreCheck[aP.target:lower()] then
        writeLog(string.format("!!!! Unrecognized target [%s].", aP.target), EZMobUtils.STATUS.WARN)
    end

    aP.targetDistance = aI
    writeDebug("DISTANCETARGET:: 10 aP.targetDistance %s", json(aP.targetDistance))

    writeLog("Parsing Ability Distance and Target complete.", EZMobUtils.STATUS.INFO, -1)
end

--- Validates that a match object contains all expected characteristics within acceptable ranges.
--- Checks each characteristic from the game engine configuration is present and between -100 and 100.
--- @param match table The regex match object containing characteristic values to validate.
--- @return boolean valid `true` if all characteristics are present and within range; `false` otherwise.
function EZMobMonsterParser:_validateCharacteristics(match)
    if match then
        for _, key in ipairs(EZMobConfig.validations.monster.characteristics) do
            local val = tonumber(match[key])
            if not val or val < -100 or val > 100 then
                return false
            end
        end
        return true
    end
    return false
end