local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- @class EZMobTextMaliceParser : EZMobTextLineParser
--- @field name string The name of the monster group being parsed.
--- @field importOptions table Optional configuration passed in via import context.
--- @field isImportable boolean Whether the monster group passed validation and can be imported.
--- @field monsterGroup table A Codex MonsterGroup representing the parsed group.
EZMobTextMaliceParser = RegisterGameType("EZMobTextMaliceParser", "EZMobTextLineParser")
EZMobTextMaliceParser.__index = EZMobTextMaliceParser

--- Creates a new `EZMobTextMaliceParser` instance from a given 
--- Initializes parser state and working group structure.
--- @param entry table A table containing `name` and `text` fields representing the monster group.
--- @return table|nil instance A new parser instance or nil if no entry was provided.
function EZMobTextMaliceParser:new(entry)
    if not entry then return end

    writeDebug("EZMobTextMaliceParser CREATE for [%s]", entry.name)

    local instance = setmetatable(EZMobTextLineParser:new(entry.text), self)

    instance.name = entry.name
    instance.importOptions = import.options or {}
    instance.isImportable = true
    instance.monsterGroup = {}

    return instance
end

function EZMobTextMaliceParser:ParseAbility(a)
    writeLog(string.format("Parse Ability [%s] starting.", a.name), EZMobUtils.STATUS.INFO, 1)

    while not self.eof do
        local sLine = self:_getNextLine()
        local abilityMatch = regex.MatchGroups(sLine, EZMobConfig.regex.malice.body.ability.name)
        if abilityMatch ~= nil then
            self:_putLine()
            break
        end
        if a.description ~= "" then a.description = a.description .. "\n" end
        a.description = a.description .. sLine
    end

    writeLog(string.format("Parse Ability [%s] complete.", a.name), EZMobUtils.STATUS.INFO, -1)

    return #a.description > 0
end

function EZMobTextMaliceParser:ParseBody()

    self.curLine = 1  -- Start from line 2
    while not self.eof do
        local sLine = self:_getNextLine()

        writeDebug("PARSEBODY BODYLINE [%s]", sLine)

        local abilityMatch = regex.MatchGroups(sLine, EZMobConfig.regex.malice.body.ability.name)
        if abilityMatch then
            writeDebug("PARSEBODY ABILITY %s", json(abilityMatch))

            -- Find or create the ablity
            local a = nil
            for _,ability in ipairs(self.monsterGroup.maliceAbilities) do
                if ability.name:lower() == abilityMatch.abilityName:lower() then
                    a = ability
                    break
                end
            end
            if a == nil then
                a = MaliceAbility.Create{
                    name = abilityMatch.abilityName,
                }
            end

            a.description = ""
            a.resourceCost = CharacterResource.maliceResourceId
            a.resourceNumber = tonumber(abilityMatch.malice)

            self.isImportable = self:ParseAbility(a)
            self.monsterGroup.maliceAbilities[#self.monsterGroup.maliceAbilities+1] = a

        end

    end
    writeDebug("PARSEBODY complete.")

    if self.isImportable then writeLog("Body parse successful.") end

    return self.isImportable
end

--- Orchestrates the full parsing process for a monster group 
--- Calls header and body parsing methods, logs progress, and returns importability status.
--- @return boolean importable `true` if the monster group was successfully parsed and marked importable; `false` otherwise.
function EZMobTextMaliceParser:Parse()
    writeLog(string.format("Parsing monster group [%s] starting.", self.name), EZMobUtils.STATUS.INFO, 1)

    local mg = import:GetExistingItem(MonsterGroup.tableName, self.name)
    if mg then
        writeLog(string.format("!!!! Monster group [%s] exists. Not importing.", self.name), EZMobUtils.STATUS.WARN)
        self.isImportable = false
    else
        self.monsterGroup = MonsterGroup.CreateNew{
            name = self.name,
        }
        self:ParseBody()
    end

    writeDebug("MALICEPARSER PARSE COMPLETE [%s] importable [%s] %s", self.name, self.isImportable, json(self.monsterGroup))
    writeLog(string.format("Parsing monster group [%s] complete.", self.name), EZMobUtils.STATUS.INFO, -1)

    return self.isImportable
end

--- Handles the full import process for a Monster Group, including parsing, validation, and monster group entry creation.
--- If parsing is successful, a new or updated monster group entry is created.
--- If the entry is eligible for import, it is passed to the system's import mechanism.
--- Logs all steps and gracefully handles non-importable entries.
function EZMobTextMaliceParser:Import()
    writeLog(string.format("Importing Monster Group [%s].", self.name), EZMobUtils.STATUS.IMPL)
    import:ImportAsset(MonsterGroup.tableName, self.monsterGroup)
    writeLog(string.format("Monster Group import for [%s] complete.", self.name), EZMobUtils.STATUS.INFO, -1)
end
