-- Gate raw LuaCov hit/miss counts for every production file, not rounded totals.
local lfs = require("lfs")
local report = assert(io.open(arg[1] or "luacov.report.out", "r"))
local records = {}
local in_summary = false
for line in report:lines() do
    if line == "Summary" then in_summary = true end
    if in_summary then
        local path, hits, missed = line:match("^(.-)%s+(%d+)%s+(%d+)%s+[%d%.]+%%$")
        if path and path ~= "Total" then
            path = path:gsub("^%./", "")
            assert(not records[path], "Duplicate coverage: " .. path)
            records[path] = { tonumber(hits), tonumber(missed) }
        end
    end
end
report:close()
assert(in_summary, "Missing LuaCov summary")

local files = {}
local function collect(directory)
    for name in lfs.dir(directory) do
        if name ~= "." and name ~= ".." then
            local path = directory .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                collect(path)
            elseif name:match("%.lua$") then
                files[#files + 1] = path
            end
        end
    end
end
collect("src")
collect("adapters")
table.sort(files)
assert(#files > 0, "No production Lua files found")

local failed = false
for _, path in ipairs(files) do
    local record = records[path]
    if not record then
        io.stderr:write("Missing coverage: " .. path .. "\n")
        failed = true
    else
        local hits, missed = record[1], record[2]
        local total = hits + missed
        local percent = total > 0 and 100 * hits / total or 0
        print(("%-48s %6.2f%% (%d/%d)"):format(path, percent, hits, total))
        if total == 0 or hits * 100 < total * 95 then
            failed = true
        end
    end
end
if failed then
    io.stderr:write("Coverage gate failed: every production file must reach 95%.\n")
    os.exit(1)
end
print(("Coverage gate passed: all %d production files reach 95%%."):format(#files))
