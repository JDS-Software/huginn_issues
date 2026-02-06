-- Copyright (c) 2026-present JDS Consulting, PLLC.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is furnished
-- to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

-- time.lua
-- UTC time handling, ID generation, timestamp parsing, age calculations


local M = {}

--- Generate a unique Huginn ID from current UTC time
---@return string id ID in format "yyyyMMdd_kkmmss"
function M.generate_id()
    local utc_time = os.date("!*t")

    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        utc_time.year,
        utc_time.month,
        utc_time.day,
        utc_time.hour,
        utc_time.min,
        utc_time.sec
    )
end

--- Parse a Huginn ID into a time structure
---@param id string Huginn ID like "20260109_143256"
---@return huginn.IdTime? parsed time structure, or nil if invalid
function M.parse_id(id)
    if not id or type(id) ~= "string" then
        return nil
    end

    local year, month, day, hour, min, sec = id:match("^(%d%d%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)$")

    if not year then
        return nil
    end

    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        minute = tonumber(min),
        second = tonumber(sec),
    }
end

--- Get current UTC timestamp as ISO 8601 string
---@return string timestamp "YYYY-MM-DD HH:MM:SS UTC"
function M.get_utc_timestamp()
    return os.date("!%Y-%m-%d %H:%M:%S UTC")
end

--- Parse ISO 8601 timestamp string into time structure
---@param timestamp string "YYYY-MM-DD HH:MM:SS UTC"
---@return huginn.Timestamp? parsed time structure, or nil if invalid
function M.parse_timestamp(timestamp)
    if not timestamp or type(timestamp) ~= "string" then
        return nil
    end

    local year, month, day, hour, min, sec = timestamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d):(%d%d)")

    if not year then
        return nil
    end

    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        minute = tonumber(min),
        second = tonumber(sec),
    }
end

--- Convert time structure to epoch seconds (Unix timestamp)
---@param time_struct huginn.IdTime|huginn.Timestamp time structure with year, month, day, hour, minute fields
---@return integer? epoch seconds since epoch, or nil on error
local function time_to_epoch(time_struct)
    if not time_struct then
        return nil
    end

    local time_table = {
        year = time_struct.year,
        month = time_struct.month,
        day = time_struct.day,
        hour = time_struct.hour or 0,
        min = time_struct.minute or 0,
        sec = time_struct.second or 0,
    }

    -- os.time expects local time, but we need UTC
    -- Use ! prefix for UTC in os.date, but os.time doesn't have that option
    -- We need to calculate the offset
    local local_time = os.time(time_table)
    local utc_time_table = os.date("!*t", local_time)
    local utc_time = os.time(utc_time_table)
    local offset = os.difftime(local_time, utc_time)

    return local_time - offset
end

--- Convert Huginn ID to local time string for display
---@param id string Huginn ID
---@return string? formatted like "2026-01-09 09:32:56 EST", or nil if invalid
function M.id_to_local_time(id)
    local time_struct = M.parse_id(id)
    if not time_struct then
        return nil
    end

    local utc_epoch = time_to_epoch(time_struct)
    if not utc_epoch then
        return nil
    end

    local local_str = os.date("%Y-%m-%d %H:%M:%S", utc_epoch)

    local timezone = os.date("%Z", utc_epoch)
    if timezone and timezone ~= "" then
        return local_str .. " " .. timezone
    else
        return local_str
    end
end

--- Generate a unique Huginn ID from UTC time offset by a number of seconds
---@param offset_seconds number? seconds to subtract from current time (default 0)
---@return string id ID in format "yyyyMMdd_kkmmss"
function M.generate_id_with_offset(offset_seconds)
    local now = os.time()
    local adjusted = now - (offset_seconds or 0)
    local utc_time = os.date("!*t", adjusted)

    return string.format(
        "%04d%02d%02d_%02d%02d%02d",
        utc_time.year,
        utc_time.month,
        utc_time.day,
        utc_time.hour,
        utc_time.min,
        utc_time.sec
    )
end

--- Validate Huginn ID format
---@param id string potential Huginn ID
---@return boolean valid true if valid format
function M.is_valid_id(id)
    if not id or type(id) ~= "string" then
        return false
    end

    -- Check format: yyyyMMdd_kkmmss
    local year, month, day, hour, min, sec = id:match("^(%d%d%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)$")

    if not year then
        return false
    end

    month = tonumber(month)
    if month < 1 or month > 12 then
        return false
    end

    day = tonumber(day)
    if day < 1 or day > 31 then
        return false
    end

    hour = tonumber(hour)
    if hour > 23 then
        return false
    end

    min = tonumber(min)
    if min > 59 then
        return false
    end

    sec = tonumber(sec)
    if sec > 59 then
        return false
    end

    return true
end

return M
