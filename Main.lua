--[[ 
Module: EZMob Monster Importer
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Imports monsters and malice into the Codex from a simple
  text file.

Dependencies:
  THC Basic Chat Message module

Last reconcile w/ Codex import: 2025-05-20 #7
  I'm choosing not to implement the debug report introduced in v 6-7.

TODO:
  - MonsterGroup => Malice Abilities
--]]

local writeDebug = EZMobUtils.writeDebug
local writeLog = EZMobUtils.writeLog

--- Imports a list of monster entries using the specified parser class.
--- @param monsters table An array of monster entry tables to import.
--- @param parserClass table The parser class to use.
local function importMonsters(monsters, parserClass)
    if not monsters or #monsters == 0 then
        writeDebug("importMonsters No monsters found.")
        return
    end

    writeLog("Monster import starting.", EZMobUtils.STATUS.INFO, 1)

    for _, entry in ipairs(monsters) do
        local monster, source = parserClass.ParseMonster(entry)
        if monster then
            local importer = EZMobMonsterImporter:new(monster, source)
            if importer then
                importer:Import()
            else
                writeLog(string.format("!!!! Unable to create importer for Monster [%s].", entry.name), EZMobUtils.STATUS.ERROR)
            end
        else
            writeLog(string.format("!!!! Unable to create parser for Monster [%s].", entry.name), EZMobUtils.STATUS.ERROR)
        end
    end

    writeLog("Monster import complete.", EZMobUtils.STATUS.INFO, -1)
end

--- Processes raw monster block text and imports valid entries.
--- Auto-detects format based on presence of "#sun#" marker.
--- @param importer string Name or label of the importer invoking this function.
--- @param text string The raw text to be parsed and imported.
local function importEZMob(importer, text)
    text = EZMobUtils.sanitizeString(text)
    if #text == 0 then
        writeLog("No text found in input!", EZMobUtils.STATUS.WARN)
        writeDebug("No text found in input file!")
        return
    end

    local isLegacy = text:find("#sun#") ~= nil
    local format = isLegacy and "Legacy" or "Retail"
    local parserClass = isLegacy and EZMobMonsterParserLegacy or EZMobMonsterParserRetail

    writeLog(string.format("EZMOB %s importer starting.", format), EZMobUtils.STATUS.IMPL)
    writeDebug("SANITIZED\r\n%s", text)

    local monsters = parserClass.FindMonsters(text)
    writeDebug("MONSTERS %s", EZMobUtils.debugSummarizeNamedArray(monsters))
    writeLog(string.format("Found monsters: %d.", monsters and #monsters or 0), EZMobUtils.STATUS.IMPL)

    importMonsters(monsters, parserClass)

    writeLog(string.format("EZMOB %s importer complete.", format))
end

--- Registers the importer with the game
import.Register {
    id = "mcdmezmob",
    description = "EZMob: Monsters from Text!",
    input = "plaintext",
    priority = 1200,

    text = function(importer, text)
        importEZMob(importer, text)
    end,
}
