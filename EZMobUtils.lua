--- Utility class for monster import functionality.
--- 
--- `EZMobUtils` is a game-specific helper module registered via `RegisterGameType()`.
--- It provides a collection of general-purpose utility functions and shared variables 
--- used by the monster import process, including string formatting, logging, 
--- indentation tracking, and other reusable logic.
---
--- This module is designed to support the `EZMob Monster Importer` and related systems, 
--- and should be imported wherever shared utility logic is needed.

local EZMOB_VERBOSE = false
local EZMOB_DEBUG = false

--- @class EZMobUtils
EZMobUtils = RegisterGameType("EZMobUtils")
EZMobUtils.__index = EZMobUtils

--- Returns whether debug mode is currently enabled.
--- @return boolean debug `true` if debug mode is active; `false` otherwise.
function EZMobUtils.inDebugMode()
    return EZMOB_DEBUG
end

--- Writes a debug message to the debug log, if we're in debug mode
--- Suports param list like `string.format()`
--- @param fmt string Text to write
--- @param ...? string Tags for filling in the `fmt` string
function EZMobUtils.writeDebug(fmt, ...)
    if EZMOB_DEBUG and fmt and #fmt > 0 then
        print("EZMOB::", string.format(fmt, ...))
    end
end

--- Status flags for `EZMobUtils.writeLog()`
--- These control both logging behavior and text coloring
EZMobUtils.STATUS = {
    INFO  = "#aaaaaa",
    ERROR = "#aa0000",
    IMPL  = "#00aaaa",
    GOOD  = "#00aa00",
    WARN  = "#ff8c00",
}

--- Retrieves the line number from the call stack at a given level.
-- Useful for logging or debugging purposes.
--- @param level number (optional) The stack level to inspect. Defaults to 2 (the caller of this function).
--- @return number line The line number in the source file at the specified call stack level.
function EZMobUtils.curLine(level)
    level = level or 2
    return debug.getinfo(level, "l").currentline
end

--- Tracks the current indentation level for activity log messages.
--- This value is used to format output written to the user-facing log (not debug output),
--- allowing nested or hierarchical operations to visually reflect structure.
--- It is modified by logging functions to increase or decrease indentation as needed.
EZMobUtils.indentLevel = 0

--- Writes a formatted message to the log with optional status and indentation.
--- Applies color based on status and prepends indentation for nested output.
--- Typically indent at the start of a function and outdent at the end.
--- Indentation level is tracked globally and adjusted based on the `indent` value:
---   - A positive indent increases the level *after* the current message.
---   - A negative indent decreases the level *before* the current message.
---
--- @param message string The message to log.
--- @param status? string (optional) The status color code from EZMobUtils.STATUS (default: INFO).
--- @param indent? number (optional) A relative indent level (e.g., 1 to increase, -1 to decrease).
function EZMobUtils.writeLog(message, status, indent)
    status = status or EZMobUtils.STATUS.INFO
    indent = indent or 0

    if EZMOB_VERBOSE or status ~= EZMobUtils.STATUS.INFO then
        -- Apply negative indent before logging
        if indent < 0 then EZMobUtils.indentLevel = math.max(0, EZMobUtils.indentLevel + indent) end

        -- Prepend caller's line number for warnings and errors
        if status == EZMobUtils.STATUS.WARN or status == EZMobUtils.STATUS.ERROR then
            message = string.format("%d: %s", EZMobUtils.curLine(3), message)
        end

        local indentPrefix = string.rep(" ", 2 * math.max(0, EZMobUtils.indentLevel))
        local indentedMessage = string.format("%s%s", indentPrefix, message)
        local formattedMessage = string.format("<color=%s>%s</color>", status, indentedMessage)

        import:Log(formattedMessage)

        -- Apply positive indent after logging
        if indent > 0 then EZMobUtils.indentLevel = EZMobUtils.indentLevel + indent end
    end
end

--- Returns a comma-separated list of `name` values from a table of named objects,
--- or the string "(none)" if the table is empty.
--- @param a table An array of objects, each expected to have a `.name` field (string).
--- @return string result A comma-separated string of names, or "(none)" if the array is empty.
function EZMobUtils.debugSummarizeNamedArray(a)
    if #a == 0 then return "(none)" end

    local names = {}
    for _, entry in ipairs(a) do
        table.insert(names, entry.name)
    end

    return table.concat(names, ", ")
end

--- Converts a comma-separated string into a table of flags with trimmed keys.
--- Each value becomes a key in the returned table with `true` as its value.
--- @param str string A comma-separated string (may be empty or nil).
--- @return table result A flag table where keys are trimmed values and all values are `true`.
function EZMobUtils.csvToFlagList(str)
    local result = {}
    if not str or str == "" then return result end

    for value in str:gmatch("[^,]+") do
        result[value:trim()] = true
    end

    return result
end

--- Converts a string to English-style title case, if it is not already mixed case.
--- Capitalizes the first word and all significant words, while leaving small
--- conjunctions, prepositions, and articles in lowercase (unless they are the first word).
---
--- @param str string The input string to convert to title case.
--- @return string str The string converted to title case.
function EZMobUtils.toTitleCase(str)
    if not str or #str == 0 then return "" end

    -- If it's already mixed case, don't change it
    if str:lower() ~= str and str:upper() ~= str then return str end

    local function capitalize(word)
        return word:sub(1,1):upper() .. word:sub(2):lower()
    end

    local lcWords = {
        ["a"] = true, ["an"] = true, ["and"] = true, ["as"] = true, ["at"] = true,
        ["but"] = true, ["by"] = true, ["for"] = true, ["in"] = true, ["nor"] = true,
        ["of"] = true, ["on"] = true, ["or"] = true, ["so"] = true, ["the"] = true,
        ["to"] = true, ["up"] = true, ["yet"] = true, ["with"] = true
    }

    local words = {}
    local i = 0
    for word in str:lower():gmatch("%S+") do
        i = i + 1
        if i == 1 or not lcWords[word] then
            table.insert(words, capitalize(word))
        else
            table.insert(words, word)
        end
    end

    return table.concat(words, " ")
end

--- Sanitizes a string for consistent parsing and comparison.
--- Converts certain Unicode punctuation and symbols into simpler or placeholder forms,
--- normalizes whitespace, and escapes remaining non-ASCII characters using percent-encoding.
--- @param s string The input string to sanitize. If `nil`, it defaults to an empty string.
--- @return string s A sanitized version of the input string.
function EZMobUtils.sanitizeString(s)

    s = s or ""
    if #s == 0 then return s end

    -- Remove carriage returns
    s = s:gsub("\r", "")

    -- Replace non-breaking spaces (U+00A0, UTF-8 C2 A0)
    s = s:gsub("\194\160", " ")
    s = s:gsub("%s+$", "")

    -- Escape all non-ASCII characters as %XX
    local function escape(c)
        return string.format("%%%02X", string.byte(c))
    end
    s = s:gsub("([\128-\255])", escape)

    -- Replacements using percent-escaped UTF-8 sequences
    local replacements = {
        -- Special punctuation
        ["%E2%80%93"] = "-",  -- en dash
        ["%E2%80%94"] = "-",  -- em dash
        ["%E2%88%92"] = "-",  -- em dash
        ["%E2%80%98"] = "'",  -- left single quote
        ["%E2%80%99"] = "'",  -- right single quote
        ["%E2%80%9C"] = "\"", -- left double quote
        ["%E2%80%9D"] = "\"", -- right double quote
        ["%E2%80%A6"] = "...",-- ellipsis
        ["%C2%AD"]    = "-",  -- soft hyphen
        ["%C2%A0"]    = " ",  -- non-breaking space

        -- MCDM Symbols
        ["%E2%9C%A6"] = "#diamond#",    -- Diamond
        ["%E2%98%85"] = "#star#",       -- Star
        ["%E2%9C%B8"] = "#sun#",        -- Sun
        ["%E2%89%A4"] = "#lte#",        -- Less than or equal to
        ["%E2%97%86"] = " ",            -- Diamond separator
    }

    -- Apply replacements
    for hex, rep in pairs(replacements) do
        local safeHex = hex:gsub("%%", "%%%%")
        s = s:gsub(safeHex, rep)
    end

    -- Trim all whitespace down to a single space
    s = s:gsub("[ \t\f\v]+", " ")

    return s
end

--- Retrieves the ID of the "Malice" character resource, if it exists.
--- @return string|nil id The ID of the Malice resource, or nil if not found.
function EZMobUtils.getMaliceKey()
    local maliceItem = import:GetExistingItem(CharacterResource.tableName, "Malice")
    return maliceItem and maliceItem.id or nil
end

--- Attempts to find a CharacterResource ID by matching the start of the given action string.
--- Performs a case-insensitive comparison between the action and the resource name.
--- @param action string The action string to match (e.g. "maneuver", "triggered action").
--- @return string|nil id The ID of the matching CharacterResource, or nil if not found or input is invalid.
function EZMobUtils.getActionResourceId(action)
    if type(action) ~= "string" or #action == 0 then return nil end
    local t = dmhub.GetTable(CharacterResource.tableName)
    for id,res in pairs(t) do
        if action:lower():starts_with(string.lower(res.name)) then
            return id
        end
    end
    return nil
end

--- Retrieves a standard ability definition by name from the game system.
--- Uses the import interface to fetch a predefined ability from the "standardAbilities" table.
--- @param name string The name of the standard ability to retrieve.
--- @return table|nil object The standard ability object if found, or nil if not found.
function EZMobUtils.getStandardAbility(name)
    return import:GetExistingItem("standardAbilities", name)
end

--- Toggles and displays debug and verbose logging flags via a chat command.
--- Use "d" to toggle debug logging and "v" to toggle verbose logging.
--- Displays the current states of both flags in chat.
--- @param args string Optional string containing zero or more toggle flags ("d", "v").
Commands.ezmob = function(args)
    if args and #args then
        if string.find(args:lower(), "d") then EZMOB_DEBUG = not EZMOB_DEBUG end
        if string.find(args:lower(), "v") then EZMOB_VERBOSE = not EZMOB_VERBOSE end
    end
    SendTitledChatMessage(string.format("<color=#00cccc>[d]ebug:</color> %s <color=#00cccc>[v]erbose:</color> %s", EZMOB_DEBUG, EZMOB_VERBOSE), "ezmob", "#e09c9c", dmhub.userid)
end
