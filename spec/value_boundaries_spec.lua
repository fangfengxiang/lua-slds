local ShortLink = require("slds.domain.short_link")
local snapshot = require("slds.internal.snapshot")

local function link_with(fields)
    local opts = { namespace = "ns", code = "abc", target = "https://old.com" }
    for key, value in pairs(fields or {}) do opts[key] = value end
    return ShortLink.new(opts)
end

describe("ShortLink value boundaries", function()
    it("rejects invalid constructor containers and identity fields", function()
        assert.has_error(function() ShortLink.new(false) end)
        for _, fields in ipairs({ { namespace = false }, { namespace = "" }, { code = false }, { code = "" } }) do
            assert.has_error(function() link_with(fields) end)
        end
    end)

    it("rejects invalid targets and statuses before producing a value", function()
        for _, fields in ipairs({ { target = "" }, { target = false }, { status = "EXPIRED" }, { status = false } }) do
            local link, err = link_with(fields)
            assert.is_nil(link)
            assert.matches("^INVALID", err)
        end
    end)

    it("validates finite expiration on construction and patching", function()
        for _, value in ipairs({ false, "100", 0/0, math.huge, -math.huge }) do
            local link, err = link_with({ expires_at = value })
            assert.is_nil(link)
            assert.matches("^INVALID", err)
            local original = link_with({ expires_at = 100 })
            local updated, update_err = original:with_patch({ target = "https://new.com", expires_at = value })
            assert.is_nil(updated)
            assert.matches("^INVALID", update_err)
            assert.equal("https://old.com", original.target)
            assert.equal(100, original.expires_at)
        end
    end)

    it("allows finite fractional past timestamps and retains the equal boundary", function()
        local link = link_with({ expires_at = -0.5 })
        assert.is_false(link:is_expired(-0.5))
        assert.is_true(link:is_expired(0))
        local changed = assert(link:with_patch({ expires_at = 0.25 }))
        assert.is_false(changed:is_expired(0.25))
        assert.equal(0.25, changed:with_patch({}).expires_at)
    end)

    it("rejects invalid clocks even on an unexpiring link", function()
        local link = link_with()
        for _, value in ipairs({ false, "100", 0/0, math.huge, -math.huge }) do
            assert.has_error(function() link:is_expired(value) end)
        end
    end)

    it("does not interpret false patches as omitted values", function()
        local link = link_with()
        for _, patch in ipairs({ { target = false }, { status = false } }) do
            local updated, err = link:with_patch(patch)
            assert.is_nil(updated)
            assert.matches("^INVALID", err)
        end
        assert.has_error(function() link:with_patch(false) end)
    end)

    it("preserves metadata without interpreting an unsupported metadata patch", function()
        local link = link_with({ metadata = { nested = { owner = "old" } } })
        local updated = assert(link:with_patch({ metadata = { owner = "new" } }))
        assert.equal("old", updated.metadata.nested.owner)
        updated.metadata.nested.owner = "changed"
        assert.equal("old", link.metadata.nested.owner)
        local invalid, err = link_with({ metadata = false })
        assert.is_nil(invalid)
        assert.matches("^INVALID", err)
    end)

    it("copies cyclic table graphs and table keys without executing metatables", function()
        local key, shared = {}, { value = "original" }
        local metadata = { left = shared, right = shared }
        metadata.self = metadata
        metadata[key] = key
        setmetatable(metadata, {
            __pairs = function() error("must not execute") end,
            __index = function() error("must not execute") end,
            __metatable = "protected",
        })
        local copied = link_with({ metadata = metadata }).metadata
        assert.is_nil(getmetatable(copied))
        assert.is_true(rawequal(copied, copied.self))
        assert.is_true(rawequal(copied.left, copied.right))
        assert.is_false(rawequal(copied.left, shared))
        local copied_key
        for item in pairs(copied) do if type(item) == "table" then copied_key = item end end
        assert.is_truthy(copied_key)
        assert.is_true(rawequal(copied_key, copied[copied_key]))
        assert.is_false(rawequal(key, copied_key))
        copied.left.value = "changed"
        assert.equal("original", shared.value)
    end)

    it("retains non-table leaves without claiming to copy host resources", function()
        local resource = function() return "host" end
        local copied = snapshot({ callback = resource, enabled = true })
        assert.equal(resource, copied.callback)
        assert.equal("host", copied.callback())
        assert.is_true(copied.enabled)
    end)
end)
