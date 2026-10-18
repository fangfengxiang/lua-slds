-- Copy raw table graphs without invoking or transporting metadata metatables.
-- Non-table leaves retain their value; resource internals are host-owned.
local function copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, item in next, value do
        result[copy(key, seen)] = copy(item, seen)
    end
    return result
end

return copy
