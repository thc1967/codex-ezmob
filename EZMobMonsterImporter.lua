--[[
  @class EZMobMonsterImporter

  Imports a monster into the Codex.
  Monster table structure is as follows:

    @field name string The monster's name.
    @field level number The monster's level (challenge rating).
    @field role string The monster's role (e.g., Brute, Controller).
    @field isMinion boolean Whether the monster is a minion.
    @field keywords table<string, boolean> Flag table of monster keywords.
    @field folderName string|nil Optional folder name (taken from first keyword or explicitly defined).
    @field ev number Encounter Value (used for balancing).
    @field stamina number Max hitpoints (used for both `max_hitpoints` and `max_hitpoints_roll`).
    @field resistances table[] Array of `ResistanceEntry` objects (damage resistances, immunities, weaknesses).
    @field speed number The monster's base walking speed.
    @field size string Size code (e.g., "M", "L", "S", "T").
    @field stability number Numeric stability value for the monster.
    @field movementSpeeds table<string, number> Map of movement types (e.g., Fly, Swim) to their speeds.
    @field characteristics table<string, table> Map of 3-letter attribute codes (e.g., "mgt", "agl") to tables with `baseValue`.
    @field freeStrike number Opportunity attack value.
    @field withCaptain string|nil Optional captain-related trait description.
    @field features table[] Array of `CharacterFeature` objects representing the monster's traits.
    @field abilities table[] Array of parsed ability blocks.
    Each ability includes:
        @field name string
        @field action string
        @field signature boolean
        @field cost number
        @field target string
        @field distance string
        @field effect string|nil
        @field special string|nil
        @field trigger string|nil
        @field keywords string|nil
        @field malice table[]|nil Array of `{ name = string, description = string }`
        @field roll table|nil Optionally includes:
            @field roll string|nil Power roll (e.g., "2d10 + 3")
            @field type string "power" or "resist"
            @field resistAttr string|nil One of the attribute codes ("mgt", "agl", etc.)
            @field rollTable table Includes rollTier1, rollTier2, and rollTier3 as strings
        @field isImportable boolean Whether the ability passed validation
--]]

local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- Imports a parsed monster structure into the Codex bestiary.
--- Expects a monster table in the internal canonical format (as parsed by EZMobMonsterParserLegacy)
--- and text source of the input.
EZMobMonsterImporter = RegisterGameType("EZMobMonsterImporter")
EZMobMonsterImporter.__index = EZMobMonsterImporter

--- @param monster table The structured monster table.
--- @param source string The source text for the import.
--- @return table
function EZMobMonsterImporter:new(monster, source)
    local instance = setmetatable({}, self)
    instance.monster = monster
    instance.bestiaryEntry = nil
    instance.importOptions = import.options or {}
    instance.source = EZMobUtils.inDebugMode() == false and source or "Imported with EZMob Importer in Debug Mode.\nTurn debug mode off with /ezmob d and re-import to import source text."
    return instance
end

--- Handles the full import process for a monster, including parsing, validation, and bestiary entry creation.
--- If parsing is successful, the monster is validated for folder placement, and a new or updated bestiary entry is created.
--- If the entry is eligible for import, it is passed to the system's import mechanism.
--- Logs all steps and gracefully handles non-importable entries.
function EZMobMonsterImporter:Import()
    writeLog(string.format("Monster import for [%s] starting.", self.monster.name), EZMobUtils.STATUS.INFO, 1)

    self:_validateFolder()
    self:_setMonsterGroup()
    if self:_createBestiaryEntry() then
        writeLog(string.format("Importing monster [%s] into folder [%s].", self.monster.name, self.monster.folderName or "(root)"), EZMobUtils.STATUS.IMPL)
        import:ImportMonster(self.bestiaryEntry)
    end

    writeLog(string.format("Monster import for [%s] complete.", self.monster.name), EZMobUtils.STATUS.INFO, -1)
end

--- Creates or retrieves a bestiary entry for the current monster and populates it with all parsed data.
--- If an existing entry is found and marked as protected from overwrite (`import.override`), the import is aborted.
--- Otherwise, creates a new monster entry or updates an existing one based on import options.
--- Maps monster data including name, stats, abilities, traits, keywords, movement, and source metadata.
--- @private
--- @return boolean success `true` if the bestiary entry was created or updated successfully, `false` if the entry was protected.
function EZMobMonsterImporter:_createBestiaryEntry()
    writeDebug("CREATEBESTIARYENTRY [%s]", self.monster.name)
    writeLog(string.format("Create bestiary entry for [%s] starting.", self.monster.name), EZMobUtils.STATUS.INFO, 1)
    local be

    if self.importOptions.replaceExisting ~= false then
        be = import:GetExistingItem("monster", self.monster.name)
    end

    -- If we got an entry, and it's imported, and the override is true, we're not to import.
    if be ~= nil then
        writeLog(string.format("Monster [%s] exists. Checking override.", self.monster.name))
        if be.properties:has_key("import") and be.properties.import.override then
            writeLog(string.format("!!!! [%s] bestiary entry is protected from overwrite. Not importing.", self.monster.name), EZMobUtils.STATUS.WARN, -1)
            return false
        end
    end

    if be == nil then
        writeLog("New monster. Creating token.", EZMobUtils.STATUS.IMPL)
        be = import:CreateMonster()
        be.properties = monster.CreateNew()
    end

    be.name = self.monster.name
    be.parentFolder = self.monster.folderId

    self.bestiaryEntry = be

    local m = be.properties
    local im = self.monster

    m.name = im.name
    m.groupid = im.groupid
    m.reach = nil
    m.monster_category = next(im.keywords) or "Monster"
    m.monster_type = im.name
    m.role = im.role
    m.minion = im.isMinion
    m.cr = im.level
    m.ev = im.ev
    m.keywords = im.keywords
    m.creatureSize = im.size
    m.stability = im.stability or 99
    m.max_hitpoints = im.stamina
    m.max_hitpoints_roll = im.stamina
    m.resistances = im.resistances
    m.walkingSpeed = im.speed
    m.movementSpeeds = im.movementSpeeds
    m.attributes = im.characteristics
    m.opportunityAttack = im.freeStrike or 1
    m.withCaptain = im.withCaptain
    m.characterFeatures = self:_importFeatures()
    m.innateActivatedAbilities = self:_importAbilities()
    m.import = self:_importSource()

    writeDebug("IMPORTING:: %s", json(m))

    writeLog(string.format("Create bestiary entry for [%s] complete.", self.monster.name), EZMobUtils.STATUS.INFO, -1)
    return true
end

--- Imports all validated abilities from the parsed monster and transforms them into `ActivatedAbility` objects.
--- Iterates through each ability in `self.monster.abilities`, using `EZMobAbilityImporter` to perform the import if the ability is marked as importable.
--- Logs progress and skips any abilities flagged as non-importable.
--- @private
--- @return table abilities An array of successfully imported `ActivatedAbility` objects.
function EZMobMonsterImporter:_importAbilities()
    writeLog("Import Abilities starting.", EZMobUtils.STATUS.INFO, 1)

    local abilities = {}

    for _,ability in ipairs(self.monster.abilities or {}) do
        writeLog(string.format("Ability [%s] starting.", ability.name), EZMobUtils.STATUS.INFO, 1)
        if ability.isImportable then
            writeLog(string.format("Importing Ability [%s].", ability.name), EZMobUtils.STATUS.IMPL)
            writeDebug("DISTANCETARGET:: 15 ability %s", json(ability))

            local abilImporter = EZMobAbilityImporter:new(self.bestiaryEntry, ability)
            if abilImporter ~= nil then
                local newAbility = abilImporter:Import()
                writeDebug("DISTANCETARGET:: 99 newAbility %s", json(newAbility))
                if newAbility ~= nil then
                    abilities[#abilities + 1] = newAbility
                end
            end
        else
            writeLog(string.format("Ability [%s] is not importable.", ability.name), EZMobUtils.STATUS.WARN)
        end
        writeLog(string.format("Ability [%s] complete.", ability.name), EZMobUtils.STATUS.INFO, -1)
    end

    writeLog("Import Abilities complete.", EZMobUtils.STATUS.INFO, -1)
    return abilities
end

--- Parses raw monster feature data into fully constructed `CharacterFeature` objects.
--- Each feature is assigned a GUID, domains, source, and any matching trait modifiers.
--- Attempts to match each feature against known templates from `importerMonsterTraits`.
--- @private
--- @return table features An array of `CharacterFeature` objects ready for import.
function EZMobMonsterImporter:_importFeatures()
    writeLog("Importing features starting.", EZMobUtils.STATUS.INFO, 1)

    local features = {}

    for _,inputFeature in ipairs(self.monster.features or {}) do
        local guid = dmhub.GenerateGuid()
        local feature = CharacterFeature.new {
            guid = guid,
            name = inputFeature.name,
            description = inputFeature.description,
            domains = {
                [string.format("CharacterFeature:%s", guid)] = true,
            },
            source = "Trait",
            modifiers = {},
        }

        local featureTemplates = dmhub.GetTable("importerMonsterTraits") or {}
        for _,v in pairs(featureTemplates) do
            local trait = v:MatchMCDMMonsterTrait(nil, feature.name, feature.description)
            if trait ~= nil then
                feature.implementation = trait:try_get("implementation")
                feature.modifiers = DeepCopy(trait.modifiers)
                for _,mod in ipairs(feature.modifiers) do
                    mod.description = feature.description
                end
                break
            end
        end

        writeLog(string.format("Adding Feature [%s].", feature.name), EZMobUtils.STATUS.IMPL)
        features[#features + 1] = feature
    end

    writeLog("Importing features complete.", EZMobUtils.STATUS.INFO, -1)
    return features
end

--- Builds the source metadata for the imported bestiary entry.
--- This is used to attach the original text block (source data) to the entry for reference or traceability.
--- @private
--- @return table source A table with `type = "mcdm"` and `data` containing the raw text from the parsed monster.
function EZMobMonsterImporter:_importSource()
    return {
        type = "mcdm",
        data = self.source,
    }
end

--- Determines the appropriate monster group from the folder name
function EZMobMonsterImporter:_setMonsterGroup()
    local folderName = self.monster.folderName or ""
    if #folderName == 0 then return end
    writeDebug("SETMONSTERGROUP:: [%s]", folderName)

    local monsterGroup = import:GetExistingItem(MonsterGroup.tableName, folderName)
    if monsterGroup then
        writeDebug("SETMONSTERGROUP:: SETTING:: [%s] [%s]", monsterGroup.name, monsterGroup.id)
        self.monster.groupid = monsterGroup.id
    end
end

--- Determines the appropriate folder for the monster and ensures it exists.
--- Uses the monster's assigned folder name or falls back to the first keyword.
--- Creates and registers the folder if it doesn't already exist.
function EZMobMonsterImporter:_validateFolder()
    local folderName = self.monster.folderName or ""
    writeDebug("VALIDATEFOLDER:: [%s]", folderName)

    -- If we still don't have a folder name, we're out.
    if #folderName == 0 then
        writeLog("!!!! Folder name can't be found in import.", EZMobUtils.STATUS.WARN)
        return
    end

    -- Get or create the folder
    local folder = import:GetExistingItem("monsterFolder", folderName)
    if folder == nil then
        writeDebug("VALIDATEFOLDER:: CREATE FOLDER [%s]", folderName)
        folder = import:CreateMonsterFolder(folderName)
        import:ImportMonsterFolder(folder)
    else
        writeDebug("VALIDATEFOLDER:: FOUND FOLDER [%s]", folder.id)
    end
    self.monster.folderId = folder.id

    writeDebug("VALIDATEFOLDER:: id [%s] descr [%s]", folder.id, folder.description)
    writeLog(string.format("Importing monster into folder [%s]", folderName))
end