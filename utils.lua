local lfs = require("libs/libkoreader-lfs")

local Utils = {}

function Utils.join_tables(target, source)
    return table.move(source, 1, #source, #target + 1, target)
end

function Utils.file_exists(path)
    if path == nil then return nil end
    return lfs.attributes(path) ~= nil
end

function Utils.table_contains(t,  search_value)
    for _, v in pairs(t) do
        if v == search_value then
            return true
        end
    end

    return false
end

function Utils.file_slurp(path)
    if not Utils.file_exists(path) then
        return nil
    end
    local f = io.open(path, "r")

    if f == nil then
        return nil
    end

    local content = f:read("*all")
    f:close()
    return content
end


return Utils