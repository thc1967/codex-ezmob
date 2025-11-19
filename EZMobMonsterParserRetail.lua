local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- @class EZMobMonsterParserRetail
--- @field name string The name of the monster being parsed
--- @field table monster An internal representation of the parsed monster
--- @field importOptions table Optional configuration passed in via import context.
--- @field isImportable boolean Whether the monster group passed validation and can be imported.
--- Parses an array of text lines into a structured monster table.
--- Used for transforming text input (e.g., from a bestiary entry) into a standard monster data structure.
--- This is the first stage of the import process.
EZMobMonsterParserRetail = RegisterGameType("EZMobMonsterParserRetail", "EZMobMonsterParser")
EZMobMonsterParserRetail.__index = EZMobMonsterParserRetail

function EZMobMonsterParserRetail:new(entry)
    if not entry then return end
    local instance = setmetatable(EZMobMonsterParser:new(entry), self)
    return instance
end

--- Static function to find and extract monster blocks from text.
--- Searches for monster headers and groups associated text lines into structured entries.
--- @param text string The full input text to parse.
--- @return table monsters An array of monster objects, each with a `name` and `text` array.
function EZMobMonsterParserRetail.FindMonsters(text)
    return EZMobMonsterParser.FindMonsters(text, EZMobConfig.regex.monster.retail.header.name)
end

--- Static function to parse a single monster entry into a structured monster object.
--- Creates a parser instance, attempts to parse the entry, and returns the results.
--- @param entry table A monster entry containing `name` and `text` fields.
--- @return table|nil monster The parsed monster object on success, or nil on failure.
--- @return table|nil source The source information object on success, or nil on failure.
function EZMobMonsterParserRetail.ParseMonster(entry)
    return EZMobMonsterParser.ParseMonster(EZMobMonsterParserRetail, entry)
end

--- Parses the content of a monster ability block, starting from the current line.
--- Handles optional roll syntax, ability detail lines, features, and embedded roll table entries.
--- @param am table The ability object being populated.
function EZMobMonsterParserRetail:_parseAbility(am)
    writeLog(string.format("Parse Ability [%s] starting.", am.name), EZMobUtils.STATUS.INFO, 1)

    local function calcAction()
        -- if am.villainAction and tonumber(am.villainAction) > 0 then return "Villain Action " .. am.villainAction end
        return "Main Action"
    end

    local function calcCategorization()
        writeDebug("CATEGORIZATION:: [%s]\n%s", am.name, json(am))
        if am.malice and tonumber(am.malice) > 0 then return "Heroic Ablity" end
        if am.villainAction and tonumber(am.villainAction) > 0 then return "Villain Action" end
        return "Signature Ability"
    end

    local function calcVillainAction()
        if am.villainAction and tonumber(am.villainAction) > 0 then
            return "Villain Action " .. am.villainAction
        end
        return nil
    end

    local a = {
        name = am.name:trim(),
        action = calcAction(),
        categorization = calcCategorization(),
        villainAction = calcVillainAction(),
        signature = #(am.signature or "") > 0,
        cost = tonumber(am.malice) or 0,
        target = "1 creature or object",
        distance = "1",
        isImportable = true,
    }

    -- Power roll, if there is one
    if am.roll and #am.roll > 0 then
        a.roll = a.roll or {}
        a.roll.roll = am.roll
        a.roll.type = "power"
    end

    while not self.eof do
        local sLine = self:_getNextLine()

        -- Blank lines end abilities
        if sLine == "" then break end

        -- Match this line to any expected pattern for an ability
        local foundMatch = false
        for key,pattern in pairs(EZMobConfig.regex.monster.retail.body.ability.body) do
            local match = regex.MatchGroups(sLine, pattern)
            if match then
                foundMatch = true
                writeDebug("PARSEBODY PARSEABILITY MATCH [%s]", json(match))

                if key == "rollTier1" or key == "rollTier2" or key == "rollTier3" then
                    writeDebug("ROLLTIER:: [%s]->[%s]", key, match.effect)
                    a.roll = a.roll or {}
                    a.roll.rollTable = a.roll.rollTable or {}
                    a.roll.rollTable[key] = match.effect
                elseif "keywordsAction" == key then
                    a.keywords = match.keywords
                    if match.action then
                        a.action = match.action
                        if match.action:lower():find("trigger") then
                            a.categorization = "Trigger"
                        end
                    end
                elseif "distanceTarget" == key then
                    writeDebug("DISTANCETARGET:: d=[%s] t=[%s] [%s]", match.distance, match.target or "", sLine)
                    a.distance = match.distance or ""
                    a.target = match.target or ""
                elseif "effect" == key or "special" == key or "trigger" == key then
                    local f = {
                        name = key,
                        description = match.description
                    }
                    self:_parseFeature(f, EZMobConfig.regex.monster.retail.body.feature.enders)
                    a[key] = f.description
                elseif "malice" == key then
                    writeDebug("MALICE:: [%s]", sLine)
                    local f = {
                        name = match.malice,
                        description = match.description
                    }
                    self:_parseFeature(f, EZMobConfig.regex.monster.retail.body.feature.enders)
                    a[key] = a[key] or {}
                    table.insert(a[key], f)
                else
                    writeLog(string.format("ERROR: matched key [%s] not processed.", key), EZMobUtils.STATUS.ERROR)
                    writeDebug("ERROR:: PARSEABILITY matched key [%s] not processed.", key)
                end
            end
        end

        -- The first time we find a nonmatching line, we have reached the end of the ability
        if not foundMatch then
            self:_putLine()
            break
        end
    end

    self._validateAbility(a)

    writeDebug("PARSEABILITY isImportable [%s] %s", tostring(a.isImportable), json(a))
    writeLog(string.format("Parse Ability [%s] complete. Valid = [%s].", a.name, tostring(a.isImportable)), EZMobUtils.STATUS.INFO, -1)

    return a
end

--- Parses the body of the monster entry, starting from line 7.
--- Iterates through lines using `_getNextLine()` until `self.eof` is true.
--- Routes lines to feature, solo, or ability processing based on regex matches.
--- @return boolean success `true` if body parsing completes successfully; `false` otherwise.
function EZMobMonsterParser:_parseBody()
    writeDebug("PARSEBODY start eof [%s] #text [%d].", self.eof, #self.lines)

    self.curLine = 7    -- start on line 8
    while not self.eof do
        local sLine = self:_getNextLine()
        writeDebug("PARSEBODY BODYLINE [%s]", sLine)

        local soloMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.body.solo.name)
        local featureMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.body.feature.name)
        local abilityMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.body.ability.name)

        if featureMatch then
            writeDebug("PARSEBODY FEATURE %s", json(featureMatch))
            local feature = {
                name = featureMatch.name or "",
                description = featureMatch.description or ""
            }
            self:_parseFeature(feature, EZMobConfig.regex.monster.retail.body.feature.enders)
            self.monster.features = self.monster.features or {}
            table.insert(self.monster.features, feature)
        elseif soloMatch then
            writeDebug("PARSEBODY SOLO %s", json(soloMatch))
            self:_parseSoloFeatures()
        elseif abilityMatch then
            writeDebug("PARSEBODY ABILITY %s", json(abilityMatch))
            local a = self:_parseAbility(abilityMatch)
            if a.isImportable then
                self.monster.abilities = self.monster.abilities or {}
                table.insert(self.monster.abilities, a)
            end
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
function EZMobMonsterParserRetail:_parseCharacteristicsLine()

    -- line 7 contains Characteristics
    local sLine = self:_getLine(7)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.characteristics)
    if self:_validateCharacteristics(match) then
        self.monster.characteristics = self:_mapCharacteristics(match)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Characteristics line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("RETAILARSER PARSEHEADER BADCHARACTERISTICS [%s]", sLine)
    end

    return self.isImportable
end

--- Parses all header-related lines of a monster entry in sequence.
--- This method drives the full header parsing workflow, calling helper methods to extract and validate
--- monster name, keywords, EV, stamina, immunity, size, speed, stability, traits, free strike, and characteristics.
--- Sets `self.isImportable` to `false` if any step fails validation.
--- @return boolean success `true` if the header was successfully parsed and marked importable; `false` otherwise.
function EZMobMonsterParserRetail:_parseHeader()
    writeDebug("RETAILPARSER PARSEHEADER for [%s]", self.name)

    self:_parseMonsterNameLine()
    self:_parseKeywordsEvLine()
    self:_parseSsssfsLine()
    self:_parseImmunityWeaknessLine()
    self:_parseMovementCaptainLine()
    self:_parseCharacteristicsLine()

    if self.isImportable then writeLog("Header parse successful.") end

    return self.isImportable
end

--- Parses the immunity and weakness line of a monster entry.
--- Extracts immunities and weaknesses from line 5 using regex matching.
--- On success, processes immunities with positive multiplier and weaknesses with negative multiplier.
function EZMobMonsterParserRetail:_parseImmunityWeaknessLine()

    -- Line 5 is immunities & weaknesses
    local sLine = self:_getLine(5)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.immunityWeakness)
    writeDebug("RETAILPARSER:: IMMUNITYWEAKNESS:: LINE:: [%s]", sLine)
    print("RETAILPARSER:: IMMUNITYWEAKNESS:: RESULT::", json(match))
    if match then
        writeDebug("RETAILPARSER:: IMMUNITYWEAKNESS:: I [%s] W [%s]", match.immunities, match.weaknesses)
        self:_parseImmunities(match.immunities, 1)
        self:_parseImmunities(match.weaknesses, -1)
    end

end

--- Parses the keywords and EV (Encounter Value) line of a monster entry.
--- Uses a configured regex to extract the EV and a comma-separated list of keywords.
--- Validates that EV is within an acceptable numeric range and that keywords are present.
--- On success, assigns values to `self.monster.keywords` and `self.monster.ev`; on failure, marks the entry as not importable.
--- @return boolean success `true` if parsing and validation succeeded; `false` otherwise.
function EZMobMonsterParserRetail:_parseKeywordsEvLine()

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
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.keywordsEv)
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
function EZMobMonsterParserRetail:_parseMonsterNameLine()

    local function isValidMonsterHeader(match)
        if match == nil then return false end
        local level = tonumber(match.level or 0)
        local role = match.role or ""
        return level >= 1 and #role > 0
    end

    -- Line 1 is the header, from which we extract name, level, type, and whether it's a minion
    local sLine = self:_getLine(1)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.name)
    if isValidMonsterHeader(match) then
        self.monster.level = tonumber(match.level)
        self.monster.role = EZMobUtils.toTitleCase(match.role)
        self.monster.isMinion = match.minion and match.minion:lower():match("minion") ~= nil
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad header for monster %s", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("RETAILPARSER PARSEHEADER BADHEADER [%s]", sLine)
    end

    return self.isImportable
end

--- Parses the movement and captain line of a monster entry.
--- Extracts movement types and captain traits from line 6 using regex matching.
--- On success, maps movement speeds and assigns captain traits to `self.monster`.
--- On failure, marks the entry as not importable and logs diagnostics.
function EZMobMonsterParserRetail:_parseMovementCaptainLine()

    -- Line 6 is movement
    local sLine = self:_getLine(6)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.movementCaptain)
    writeDebug("RETAILPARSER MOVEMENT [%s] [%s]", match.movement, match.withCaptain)
    if match ~= nil then
        self.monster.movementSpeeds = self:_mapMoveSpeeds(match.movement)
        self.monster.withCaptian = match.withCaptain
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad movement / captain for %s", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("RETAILPARSER PARSEHEADER BADMOVECAPTAIN [%s]", sLine)
    end

end

--- Parses solo feature blocks from the monster entry.
--- Iterates through lines matching them against solo feature regex patterns.
--- Creates feature objects with name and description, then processes them with `_parseFeature`.
--- Stops when a line doesn't match the expected pattern or EOF is reached.
function EZMobMonsterParserRetail:_parseSoloFeatures()

    while not self.eof do
        local sLine = self:_getNextLine()
        writeDebug("PARSEBODY SOLOLINE [%s]", sLine)

        local featureMatch = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.body.solo.feature)
        if featureMatch then
            local feature = {
                name = featureMatch.name or "",
                description = featureMatch.description or ""
            }
            self:_parseFeature(feature, EZMobConfig.regex.monster.retail.body.feature.enders)
            self.monster.features = self.monster.features or {}
            table.insert(self.monster.features, feature)
        else
            self:_putLine()
            break
        end
    end
end

--- Parses the size, speed, stamina, stability, and free strike line of a monster entry.
--- Extracts and validates values from line 3 using regex matching against configured size options and numeric ranges.
--- On success, populates corresponding fields in `self.monster`; on failure, sets `self.isImportable` to `false` and logs diagnostics.
function EZMobMonsterParserRetail:_parseSsssfsLine()

    local function isValidSsssfs(match)
        if not match then return false end
        local stamina = tonumber(match.stamina or 0)
        local speed = tonumber(match.speed or 0)
        local size = self:_validSize(match.size) or ""
        local stability = tonumber(match.stability or -100)
        local freeStrike = tonumber(match.freeStrike or 0)
        return stamina > 0 and speed > 0 and #size > 0 and stability > -100 and freeStrike > 0
    end

    -- Line 3 is Size, Speed, Stamina, Stability, & Free Strike
    local sLine = self:_getLine(3)
    writeDebug("RETAILPARSER line [%s]", sLine)
    local match = regex.MatchGroups(sLine, EZMobConfig.regex.monster.retail.header.ssssfs)
    if isValidSsssfs(match) then
        self.monster.stamina = tonumber(match.stamina)
        self.monster.speed = tonumber(match.speed)
        self.monster.size = string.upper(match.size)
        self.monster.stability = tonumber(match.stability)
        self.monster.freeStrike = tonumber(match.freeStrike)
    else
        self.isImportable = false
        writeLog(string.format("!!!! Bad Size/Speed/Stam/Stab/FS line for monster %s.", self.name), EZMobUtils.STATUS.WARN)
        writeDebug("RETAILPARSER PARSEHEADER BADSSSSFS [%s]", sLine)
    end
end
