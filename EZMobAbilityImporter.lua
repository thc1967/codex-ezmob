local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- EZMobAbilityImporter
--- @class EZMobAbilityImporter
--- @field bestiaryEntry table The Codex Bestiary Entry we're working within
--- @field parsed table The parsed ability
--- @field import table The table into which we write our calculations
--- @field maliceKey string|nil The Codex GUID representing the Malice resource key
EZMobAbilityImporter = RegisterGameType("EZMobAbilityImporter")
EZMobAbilityImporter.__index = EZMobAbilityImporter

--- Creates a new instance of `EZMobAbilityImporter`.
--- Initializes the parsed ability, import structure, and resolves the malice resource key.
--- @param bestiaryEntry table The Codex BestiaryEntry object for the monster to whom the ability belongs
--- @param parsedAbility table The parsed ability data to be transformed and imported.
--- @return EZMobAbilityImporter instance A new instance of `EZMobAbilityImporter`.
function EZMobAbilityImporter:new(bestiaryEntry, parsedAbility)
    local instance = setmetatable({}, self)

    instance.bestiaryEntry = bestiaryEntry
    instance.parsed = parsedAbility
    instance.import = {}
    instance.maliceKey = EZMobUtils.getMaliceKey()

    return instance
end

--- Checks whether the parsed ability has a non-zero malice cost.
--- @return boolean result `true` if cost > 0, `false` otherwise.
function EZMobAbilityImporter:_hasCost()
    return self.parsed.cost > 0
end

--- Determines whether the parsed ability is categorized as a villain action.
--- @private
--- @return boolean result `true` if the action string starts with "villain action", `false` otherwise.
function EZMobAbilityImporter:_isVillainAction()
    return self.parsed.villainAction ~= nil and #self.parsed.villainAction > 0
end

--- Sets cost and resource-related properties on the imported ability.
--- Applies malice resource cost if present, assigns action resource ID,
--- and configures usage limits for villain actions.
--- Updates the parsed action name if it is a villain action.
--- @private
function EZMobAbilityImporter:_importCosts()

    if self:_hasCost() and self.maliceKey then
        self.import.resourceCost = self.maliceKey
        self.import.resourceNumber = self.parsed.cost
    end

    local actionResourceId = EZMobUtils.getActionResourceId(self.parsed.action)
    if actionResourceId then self.import.actionResourceId = actionResourceId end

    if self:_isVillainAction() then
        writeDebug("VILLAINACTION:: %s %s", self.parsed.action, json(self.parsed))
        self.import.villainAction = self.parsed.villainAction
        self.import.usageLimitOptions = {
            charges = "1",
            multicharge = false,
            resourceRefreshType = "encounter",
            resourceid = dmhub.GenerateGuid(),
        }
        self.parsed.action = "action"
        local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
        for k,item in pairs(resourcesTable) do
            if string.starts_with(self.parsed.action, string.lower(item.name)) then
                self.import.actionResourceId = k
                writeDebug("VILLAINACTION:: ACTIONRESOURCEID:: %s", k)
                break
            end
        end
    end

end

--- Imports roll behavior for a power-type ability.
--- Clones the standard "Ability Power Roll" behavior and injects roll tiers and base roll value
--- from the parsed data. Appends the result to `self.import.behaviors`.
--- Logs an error if the standard behavior template cannot be retrieved.
--- @private
function EZMobAbilityImporter:_importRoll()

    if self.parsed.roll then
        local abilityPowerRoll = EZMobUtils.getStandardAbility("Ability Power Roll")
        if abilityPowerRoll then
            local r = self.parsed.roll
            for _, behavior in ipairs(abilityPowerRoll.behaviors) do
                local b = DeepCopy(behavior)

                b.tiers[1] = r.rollTable.rollTier1
                b.tiers[2] = r.rollTable.rollTier2
                b.tiers[3] = r.rollTable.rollTier3

                if r.type == "power" then
                    b.roll = r.roll
                elseif r.type == "resist" and r.resistAttr and #r.resistAttr > 0 then
                    b.resistanceRoll = true
                    b.resistanceAttr = r.resistAttr
                    writeDebug("RESISTROLL:: setting [%s]", r.resistAttr)
                else
                    writeLog(string.format("!!!! Misparsed roll in ability [%s].", self.parsed.name), EZMobUtils.STATUS.ERROR)
                end

                self.import.behaviors[#self.import.behaviors + 1] = b
            end
        else
            writeLog("!!!! Unable to get standard 'Ability Power Roll'.", EZMobUtils.STATUS.ERROR)
        end
    end

end

--- Transfers parsed distance and target data to the imported ability.
---
--- Copies each key-value pair from `self.parsed.targetDistance` into the `self.import` table.
--- This applies structured targeting data such as `targetType`, `range`, `numTargets`, etc.,
--- previously calculated by `validateAbilityTargetDistance()`.
---
--- @private
function EZMobAbilityImporter:_importDistanceTarget()
    for k,v in pairs(self.parsed.targetDistance) do
        self.import[k] = v
    end
end

--- Imports and processes the effect text and behaviors for a parsed ability.
--- Copies the effect description to the import object and attempts to match it against known ability effect templates.
--- If a match is found, substitutes select values (e.g., `range`, `numTargets`, `targetType`) and merges template behaviors.
--- If the template is marked to invoke a surrounding ability, wraps the current ability as a custom behavior.
--- Adjusts behavior order based on template flags (`insertAtStart`, `invokeSurroundingAbility`).
--- Marks the ability as not implemented if no matching template is found.
--- @private
function EZMobAbilityImporter:_importEffect()
    writeLog("Importing Ability Effect starting.", EZMobUtils.STATUS.INFO, 1)

    local aP = self.parsed
    local aI = self.import

    if aP.effect and #aP.effect > 0 then
        aI.description = aP.effect

        local abilityTemplate = nil
        local effectsTemplates = dmhub.GetTable("importerAbilityEffects") or {}
        for _, v in pairs(effectsTemplates) do
            abilityTemplate = v:MatchMCDMEffect(self.bestiaryEntry, aI.name, aI.description)
            if abilityTemplate ~= nil then
                writeDebug("DISTANCETARGET:: 18 aT %s", json(abilityTemplate))
                writeLog(string.format("Matched known effect [%s].", v.name))
                break
            end
        end

        if abilityTemplate == nil then
            writeLog("Effect implementation not found.")
            aI.effectImplemented = false
        else
            --any keys we copy from the effect if they differ from the default values.
            writeDebug("DISTANCETARGET:: 16 aI %s", json(aI))
            local substituteKeys = { } --"targetType", "range", "numTargets" }
            for _, key in ipairs(substituteKeys) do
                if abilityTemplate[key] ~= ActivatedAbility[key] then
                    aI[key] = abilityTemplate[key]
                end
            end
            writeDebug("DISTANCETARGET:: 17 aI %s", json(aI))

            if abilityTemplate:try_get("invokeSurroundingAbility") then
                --we embed the new Ability within the template behavior.
                local invokeBehavior = {}
                local invokeCustom = EZMobUtils.getStandardAbility("InvokeCustom")
                if invokeCustom then
                    local invokeBehavior = invokeCustom.behaviors[1]
                    if invokeBehavior then
                        invokeBehavior.customAbility = DeepCopy(aI)
                        invokeBehavior.customAbility.guid = dmhub.GenerateGuid()
                    end
                end

                local a = DeepCopy(abilityTemplate)
                a.name = aI.name
                a.iconid = aI.iconid
                a.flavor = aI:try_get("flavor")
                a.description = aI.description
                a.categorization = aI.categorization
                a.keywords = DeepCopy(aI.keywords)
                a.display = DeepCopy(aI.display)

                if abilityTemplate:try_get("insertAtStart") then
                    --note this is inverted to what we expect since insert at start mean *our* new behaviors go before the invoked ability.
                    a.behaviors[#a.behaviors + 1] = invokeBehavior
                else
                    table.insert(a.behaviors, 1, invokeBehavior)
                end

                aI = a
                self.import = aI
            else
                if abilityTemplate:try_get("insertAtStart") then
                    local behaviors = {}
                    for _, behavior in ipairs(abilityTemplate.behaviors) do
                        behaviors[#behaviors + 1] = behavior
                    end

                    for _, behavior in ipairs(aI.behaviors) do
                        behaviors[#behaviors + 1] = behavior
                    end

                    aI.behaviors = behaviors
                else
                    for _,behavior in ipairs(abilityTemplate.behaviors) do
                        aI.behaviors[#aI.behaviors + 1] = behavior
                    end
                end
            end
        end
    end

    -- Add triggers to the effect (description) of triggered actions
    if aP.action:lower() == "triggered action" and aP.trigger and #aP.trigger > 0 then
        aI.description = string.format("%s\n**Trigger:** %s", aI.description, aP.trigger)
    end

    writeLog("Importing Ability Effects complete.", EZMobUtils.STATUS.INFO, -1)
end

--- Appends malice effects to the ability's description.
--- Iterates over parsed malice entries and adds each one to the ability's description
--- in a formatted style using Markdown-style bold headers.
--- @private
function EZMobAbilityImporter:_importMalices()
    writeLog("Importing Ability Malices starting.", EZMobUtils.STATUS.INFO, 1)

    local aP = self.parsed
    local aI = self.import

    for _,m in ipairs(aP.malice or {}) do
        writeDebug("ABILITY:: [%s] ADD MALICE:: [%s]", aI.name, m.name)
        aI.description = string.format("%s\n**%s:** %s", aI.description, m.name, m.description)
    end

    writeLog("Importing Ability Malices complete.", EZMobUtils.STATUS.INFO, -1)
end

--- Imports a parsed ability and constructs an `ActivatedAbility` object from it.
--- Performs validation and sequentially applies parsed data: cost, roll mechanics, targeting,
--- effect text, and malice enhancements. Skips import if the parsed ability is not marked as importable.
--- @return table|nil activatedAbility The constructed `ActivatedAbility` object, or `nil` if the ability is not importable.
function EZMobAbilityImporter:Import()
    if not self.parsed.isImportable then return end

    self.import = ActivatedAbility.Create {
        name = self.parsed.name,
        keywords = EZMobUtils.csvToFlagList(self.parsed.keywords),
        flavor = "",
        behaviors = {},
        categorization = self.parsed.categorization, --self:_hasCost() and "Heroic Ability" or "Signature Ability",
    }

    self:_importCosts()
    self:_importRoll()
    self:_importDistanceTarget()
    self:_importEffect()
    self:_importMalices()

    return self.import
end
