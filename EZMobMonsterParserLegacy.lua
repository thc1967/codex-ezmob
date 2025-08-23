local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- @class EZMobMonsterParserLegacy
--- @field name string The name of the monster being parsed
--- @field table monster An internal representation of the parsed monster
--- @field importOptions table Optional configuration passed in via import context.
--- @field isImportable boolean Whether the monster group passed validation and can be imported.
--- Parses an array of text lines into a structured monster table.
--- Used for transforming text input (e.g., from a bestiary entry) into a standard monster data structure.
--- This is the first stage of the import process.
EZMobMonsterParserLegacy = RegisterGameType("EZMobMonsterParserLegacy", "EZMobMonsterParser")
EZMobMonsterParserLegacy.__index = EZMobMonsterParserLegacy

function EZMobMonsterParserLegacy:new(entry)
    if not entry then return end
    local instance = setmetatable(EZMobMonsterParser:new(entry), self)
    return instance
end

--- Static function to find and extract monster blocks from text.
--- Searches for monster headers and groups associated text lines into structured entries.
--- @param text string The full input text to parse.
--- @return table monsters An array of monster objects, each with a `name` and `text` array.
function EZMobMonsterParserLegacy.FindMonsters(text)
    return EZMobMonsterParser.FindMonsters(text, EZMobConfig.regex.monster.legacy.header.name)
end

--- Static function to parse a single monster entry into a structured monster object.
--- Creates a parser instance, attempts to parse the entry, and returns the results.
--- @param entry table A monster entry containing `name` and `text` fields.
--- @return table|nil monster The parsed monster object on success, or nil on failure.
--- @return table|nil source The source information object on success, or nil on failure.
function EZMobMonsterParserLegacy.ParseMonster(entry)
    return EZMobMonsterParser.ParseMonster(EZMobMonsterParserLegacy, entry)
end

--- Parses the content of a monster ability block, starting from the current line.
--- Handles optional roll syntax, ability detail lines, features, and embedded roll table entries.
--- @param a table The ability object being populated.
function EZMobMonsterParserLegacy:_parseAbility(a)
    writeLog(string.format("Parse Ability [%s] starting.", a.name), EZMobUtils.STATUS.INFO, 1)

    -- Try to find a power roll in the current line
    local sLine = self:_getLine()
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.body.ability.roll)
    if match and match.roll then
        a.roll = a.roll or {}
        a.roll.roll = match.roll
        a.roll.type = "power"
    end

    while not self.eof do
        sLine = self:_getNextLine()

        -- Blank lines end abilities
        if sLine == "" then break end

        -- Match this line to any expected pattern for an ability
        local foundMatch = false
        for key,pattern in pairs(EZMobConfig.regex.monster.legacy.body.ability.body) do
            match = regex.MatchGroups(sLine, pattern)
            if match then
                foundMatch = true
                if key == "rollTier1" or key == "rollTier2" or key == "rollTier3" then
                    a.roll = a.roll or {}
                    a.roll.rollTable = a.roll.rollTable or {}
                    a.roll.rollTable[key] = match.effect
                elseif "distanceTarget" == key then
                    writeDebug("DISTANCETARGET:: d=[%s] t=[%s] [%s]", match.distance, match.target or "", sLine)
                    a.distance = match.distance
                    a.target = match.target or ""
                elseif key == "special" or key == "effect" or key == "target" or key == "trigger" then
                    local f = {
                        name = key,
                        description = match.description,
                    }
                    self:_parseFeature(f, EZMobConfig.regex.monster.legacy.body.feature.enders)
                    a[key] = f.description
                elseif "malice" == key then
                    local f = {
                        name = match.key,
                        description = match.description
                    }
                    self:_parseFeature(f, EZMobConfig.regex.monster.legacy.body.feature.enders)
                    a[key] = a[key] or {}
                    table.insert(a[key], f)
                elseif "keywords" == key then
                    a[key] = match.description
                else
                    writeLog(string.format("ERROR: matched key [%s] not processed.", key), EZMobUtils.STATUS.ERROR)
                    writeDebug("ERROR:: PARSEABILITY matched key [%s] not processed.", key)
                end
                break   -- Only one pattern should match any line, so next line
            end
        end
        -- The first time we find a nonmatching line,
        -- we have reached the end of the ability
        if not foundMatch then
            self:_putLine()
            break
        end
    end

    self._validateAbility(a)
    writeDebug("DISTANCETARGET:: 13 a.targetDistance %s", json(a.targetDistance))

    writeDebug("PARSEABILITY isImportable [%s] %s", tostring(a.isImportable), json(a))
    writeLog(string.format("Parse Ability [%s] complete. Valid = [%s].", a.name, tostring(a.isImportable)), EZMobUtils.STATUS.INFO, -1)

    return a.isImportable
end

--- Parses the body of the monster entry, starting from line 7.
--- Iterates through lines using `_getNextLine()` until `self.eof` is true.
--- Routes lines to feature or ability processing based on regex matches.
--- @return boolean success `true` if body parsing completes successfully; `false` otherwise.
function EZMobMonsterParserLegacy:_parseBody()
    writeDebug("PARSEBODY start eof [%s] #text [%d].", self.eof, #self.lines)

    local function getCategorization(match, action)
        if not match then return "Signature Ability" end
        if action:starts_with("villain action") or match.vp then
            return "Heroic Ability"
        elseif action:starts_with("triggered action") then
            return "Trigger"
        end
        return "Signature Ability"
    end

    local function validateAction(action)
        if type(action) == "string" and action:lower() == "action" then
            return "Main Action"
        end
        return action
    end

    self.curLine = 6  -- Start from line 7
    while not self.eof do
        local sLine = self:_getNextLine()

        writeDebug("PARSEBODY BODYLINE [%s]", sLine)
        local featureMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.body.feature.name)
        local abilityMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.body.ability.name)

        if featureMatch then
            writeDebug("PARSEBODY FEATURE %s", json(featureMatch))
            local feature = {
                name = featureMatch.name,
                description = featureMatch.description,
            }
            self:_parseFeature(feature, EZMobConfig.regex.monster.legacy.body.feature.enders)
            self.monster.features = self.monster.features or {}
            table.insert(self.monster.features, feature)
        elseif abilityMatch then
            writeDebug("PARSEBODY ABILITY %s", json(abilityMatch))
            local action = validateAction(abilityMatch.action or "")
            local ability = {
                name = abilityMatch.name:trim(),
                action = action,
                categorization = getCategorization(abilityMatch, action),
                signature = (abilityMatch.signature or ""):lower() == "signature",
                cost = tonumber(abilityMatch.vp) or 0,
                target = "1 creature or object",
                distance = "1"
            }
            self:_parseAbility(ability)
            self.monster.abilities = self.monster.abilities or {}
            table.insert(self.monster.abilities, ability)
        end
    end

    writeDebug("PARSEBODY complete.")

    if self.isImportable then writeLog("Body parse successful.") end

    return self.isImportable
end

--- Parses and validates the characteristics line of a monster entry.
--- Expects a line containing names and numeric values for the 6 Draw Steel characteristics.
--- Extract values and ensures each is a number between -10 and 10.
--- On success, populates `self.monster.characteristics`; on failure, sets `self.isImportable` to `false` and logs diagnostics.
--- @return boolean success `true` if characteristics were successfully parsed and validated; `false` otherwise.
function EZMobMonsterParserLegacy:_parseCharacterisitcs()

    -- Line 6 contains Characteristics
    local sLine = self:_getLine(6)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.characteristics)
    if self:_validateCharacteristics(match) then
        self.monster.characteristics = self:_mapCharacteristics(match)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Characteristics line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("MONSTERPARSER PARSEHEADER BADCHARACTERISTICS [%s]", sLine)
    end

    return self.isImportable
end

--- Parses all header-related lines of a monster entry in sequence.
--- This method drives the full header parsing workflow, calling helper methods to extract and validate
--- monster name, keywords, EV, stamina, immunity, size, speed, stability, traits, free strike, and characteristics.
--- Sets `self.isImportable` to `false` if any step fails validation.
--- @return boolean success `true` if the header was successfully parsed and marked importable; `false` otherwise.
function EZMobMonsterParserLegacy:_parseHeader()

    writeDebug("LEGACYPARSER PARSEHEADER for [%s]", self.name)

    self:_parseMonsterNameLine()
    self:_parseKeywordsEvLine()
    self:_parseStaminaImmunityLine()
    self:_parseSizeSpeedStabilityLine()
    self:_parseTraitsFreeStrikeLine()
    self:_parseCharacterisitcs()

    if self.isImportable then writeLog("Header parse successful.") end

    return self.isImportable
end

--- Parses the keywords and EV (Encounter Value) line of a monster entry.
--- Uses a configured regex to extract the EV and a comma-separated list of keywords.
--- Validates that EV is within an acceptable numeric range and that keywords are present.
--- On success, assigns values to `self.monster.keywords` and `self.monster.ev`; on failure, marks the entry as not importable.
--- @return boolean success `true` if parsing and validation succeeded; `false` otherwise.
function EZMobMonsterParserLegacy:_parseKeywordsEvLine()

    --- @param match table Keyword search results
    --- @return boolean result `true` if the match is valid; `false` otherwise
    local function isValidKeywordsEv(match)
        if not match then return false end
        local ev = tonumber(match.ev or 0)
        local keywords = match.keywords or ""
        return ev > 0 and #keywords > 0
    end

    -- Line 2 is keywords and EV
    local sLine = self:_getLine(2)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.keywordsEv)
    if isValidKeywordsEv(match) then
        self.monster.keywords = EZMobUtils.csvToFlagList(match.keywords)
        self.monster.folderName = match.keywords and match.keywords:match("^[^,%s]+") or nil
        self.monster.ev = tonumber(match.ev)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Keywords-EV line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("PARSEHEADER BADKEYWORDSEV [%s]", sLine)
    end

    return self.isImportable
end

--- Parses the monster's name line to extract level, role, and minion status.
--- Uses a configured regex to extract structured values from the header line,
--- then validates that the level is between 1 and 10 and that a role is present.
--- On success, sets `self.monster.level`, `self.monster.role`, and `self.monster.isMinion`;
--- on failure, marks the entry as not importable and logs debug information.
--- @return boolean result `true` if the header was successfully parsed and validated; `false` otherwise.
function EZMobMonsterParserLegacy:_parseMonsterNameLine()

    local function isValidMonsterHeader(match)
        if match == nil then return false end
        local level = tonumber(match.level or 0)
        local role = match.role or ""
        return level >= 1 and #role > 0
    end

    -- Line 1 is the header, from which we extract name, level, type, and whether it's a minion
    local sLine = self:_getLine(1)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.name)
    if isValidMonsterHeader(match) then
        self.monster.level = tonumber(match.level)
        self.monster.role = EZMobUtils.toTitleCase(match.role)
        self.monster.isMinion = match.minion and match.minion:lower():match("minion") ~= nil
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad header for monster %s", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("MONSTERPARSER PARSEHEADER BADHEADER [%s]", sLine)
    end

    return self.isImportable
end

--- Parses the speed, size, and stability line of a monster entry.
--- Uses a configured regex to extract values for `speed`, `size`, `stability`, and optional `moveType`.
--- Validates extracted values against configured size options and ensures numeric fields are present and reasonable.
--- On success, populates corresponding fields in `self.monster`; on failure, sets `self.isImportable` to `false` and logs diagnostics.
--- @return boolean success `true` if parsing and validation succeeded; `false` otherwise.
function EZMobMonsterParserLegacy:_parseSizeSpeedStabilityLine()

    local function isValidSpeedSizeStability(match)
        if match == nil then return false end
        local speed = tonumber(match.speed or 0)
        local size = self:_validSize(match.size) or ""
        local stability = tonumber(match.stability or -100)
        writeDebug("SPEED [%s] SIZE [%s] STABILITY [%s]", speed, size, stability)
        return speed > 0 and #size > 0 and stability > -100
    end

    -- Line 4 is Speed, Size, and Stability
    local sLine = self:_getLine(4)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.speedSizeStability)
    if isValidSpeedSizeStability(match) then
        self.monster.speed = tonumber(match.speed)
        self.monster.size = string.upper(match.size)
        self.monster.stability = tonumber(match.stability)
        self.monster.movementSpeeds = self:_mapMoveSpeeds(match.moveType)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Speed-Stability line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("MONSTERPARSER PARSEHEADER BADSPEEDSTABIL [%s]", sLine)
    end

    return self.isImportable
end

--- Parses the stamina, immunities, and weaknesses line of a monster entry.
--- Uses configured regex patterns to extract and validate the monster's stamina,
--- as well as optional typed values for immunities and weaknesses.
--- On success, assigns parsed data to `self.monster`; if stamina is missing or invalid, marks the entry as not importable.
--- @return boolean success `true` if parsing and validation succeeded; `false` otherwise.
function EZMobMonsterParserLegacy:_parseStaminaImmunityLine()

    -- Line 3 is Stamina, Immunities, and Weaknesses
    local sLine = self:_getLine(3)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.stamina)
    if match and tonumber(match.stamina or 0) > 0 then
        self.monster.stamina = tonumber(match.stamina)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Stamina-Immunities line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("MONSTERPARSER PARSEHEADER BADSTAMIMM [%s]", sLine)
    end
    if not self.isImportable then return false end

    match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.immunities)
    if match then self:_parseImmunities(match.immunity, 1) end

    match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.weaknesses)
    if match then self:_parseImmunities(match.weakness, -1) end

    return self.isImportable
end

--- Parses the traits and free strike line of a monster entry.
--- Extracts the `freeStrike` value and optional `withCaptain` traits using a configured regex.
--- If `freeStrike` is present and greater than zero, the values are assigned to `self.monster`.
--- On failure, sets `self.isImportable` to `false` and logs the issue.
--- @return boolean success `true` if parsing was successful; `false` otherwise.
function EZMobMonsterParserLegacy:_parseTraitsFreeStrikeLine()

    -- Line 5 is Traits and Free Strike
    local sLine = self:_getLine(5)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.legacy.header.traitsFreeStrike)
    if match and tonumber(match.freestrike or 0) > 0 then
        self.monster.freeStrike = tonumber(match.freestrike)
        self.monster.withCaptain = match.withcaptain
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Traits - Free Strike line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("MONSTERPARSER PARSEHEADER BADTRAITSFREESTRIKE [%s]", sLine)
    end

    return self.isImportable
end
