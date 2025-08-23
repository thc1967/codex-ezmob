--- @class EZMobTextLineParser
--- Utility class for traversing and processing an array of input text lines, 
--- typically used for parsing structured monster or ability entries.
--- 
--- It provides normalized line access, navigation (next/previous), 
--- and source reconstruction capabilities. Derived parsers can build upon 
--- this to handle structured stat blocks or similar formats.
--- 
--- @field lines string[] The input text lines to parse.
--- @field curLine number The current line index (1-based).
--- @field eof boolean Whether the parser has reached the end of the input.
EZMobTextLineParser = RegisterGameType("EZMobTextLineParser")
EZMobTextLineParser.__index = EZMobTextLineParser

--- Constructor.
--- Initializes the parser with an array of input text lines.
--- @param lines string[] The array of text lines to parse.
--- @return EZMobTextLineParser instance The parser instance.
function EZMobTextLineParser:new(lines)
    local instance = setmetatable({}, self)

    instance.lines = lines or {}
    instance.curLine = 0
    instance.eof = #instance.lines == 0

    return instance
end

--- Concatenates and returns the full source text from all input lines.
--- Lines are joined with newline characters.
--- @return string fullText The joined text of all input lines.
function EZMobTextLineParser:GetSource()
    return table.concat(self.lines or {}, "\n")
end

--- Advances to the next line and returns its normalized text.
--- Increments the line pointer and updates `eof` accordingly.
--- @return string line The next normalized line or an empty string if at end.
function EZMobTextLineParser:_getNextLine()
    self.curLine = self.curLine + 1
    self.eof = self.curLine > #self.lines
    return self:_getLine()
end

--- Returns the normalized text of the specified line.
--- Defaults to the current line (`self.curLine`) if no index is provided.
--- The returned line is trimmed and has internal whitespace collapsed to a single space.
--- Returns an empty string if the line does not exist.
--- @param index number|nil Optional 1-based index of the line to retrieve.
--- @return string line The normalized text line or an empty string.
function EZMobTextLineParser:_getLine(index)
    index = index or self.curLine
    local line = self.lines[index] or ""
    return line:gsub("%s+", " "):trim()
end

--- Moves the current line pointer back by one, safely.
--- Used to "unread" a line after `_getNextLine()`.
function EZMobTextLineParser:_putLine()
    self.curLine = math.max(1, self.curLine - 1)
end
