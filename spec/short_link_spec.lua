local ShortLink = require("slds.domain.short_link")
local Lifecycle = require("slds.domain.lifecycle")

describe("ShortLink", function()
    describe("new()", function()
        it("creates with all fields", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "https://example.com",
                status = "ACTIVE",
                expires_at = 1760000000,
            })
            assert.are.equal("default", link.namespace)
            assert.are.equal("abc", link.code)
            assert.are.equal("https://example.com", link.target)
            assert.are.equal("ACTIVE", link.status)
            assert.are.equal(1760000000, link.expires_at)
        end)

        it("defaults status to ACTIVE", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "https://example.com",
            })
            assert.are.equal("ACTIVE", link.status)
        end)

        it("accepts nil expires_at", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "https://example.com",
            })
            assert.is_nil(link.expires_at)
        end)

        it("rejects javascript: scheme", function()
            local link, err = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "javascript:alert(1)",
            })
            assert.is_nil(link)
            assert.is_truthy(err)
        end)

        it("rejects data: scheme", function()
            local link, err = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "data:text/html,<script>",
            })
            assert.is_nil(link)
        end)

        it("rejects file: scheme", function()
            local link, err = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "file:///etc/passwd",
            })
            assert.is_nil(link)
        end)

        it("rejects javascript: with leading whitespace", function()
            local link, err = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "  javascript:alert(1)",
            })
            assert.is_nil(link)
            assert.is_truthy(err)
        end)

        it("rejects data: with leading whitespace", function()
            local link, err = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "\tdata:text/html,<script>",
            })
            assert.is_nil(link)
        end)

        it("accepts http:// scheme", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "http://example.com",
            })
            assert.is_truthy(link)
        end)

        it("accepts https:// scheme", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "https://example.com",
            })
            assert.is_truthy(link)
        end)

        it("stores metadata without interpretation", function()
            local link = ShortLink.new({
                namespace = "default",
                code = "abc",
                target = "https://example.com",
                metadata = { campaign = "black-friday" },
            })
            assert.are.equal("black-friday", link.metadata.campaign)
        end)
    end)

    describe("is_expired(now)", function()
        it("returns true when expires_at < now", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com",
                expires_at = 1000,
            })
            assert.is_true(link:is_expired(2000))
        end)

        it("returns false when expires_at > now", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com",
                expires_at = 3000,
            })
            assert.is_false(link:is_expired(2000))
        end)

        it("returns false when expires_at is nil", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com",
            })
            assert.is_false(link:is_expired(2000))
        end)
    end)

    it("leaves resolution decisions to Resolution", function()
        assert.is_nil(ShortLink.is_resolvable)
    end)

    describe("with_patch(patch)", function()
        it("updates target", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://old.com",
            })
            local updated = link:with_patch({ target = "https://new.com" })
            assert.are.equal("https://new.com", updated.target)
        end)

        it("updates status with valid transition", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
            })
            local updated = link:with_patch({ status = "DISABLED" })
            assert.are.equal("DISABLED", updated.status)
        end)

        it("rejects code change (immutable)", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com",
            })
            assert.has_error(function()
                link:with_patch({ code = "xyz" })
            end)
        end)

        it("rejects namespace change (immutable)", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com",
            })
            assert.has_error(function()
                link:with_patch({ namespace = "other" })
            end)
        end)

        it("rejects invalid status transition (DELETED → ACTIVE)", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "DELETED",
            })
            local updated, err = link:with_patch({ status = "ACTIVE" })
            assert.is_nil(updated)
            assert.equal("INVALID", err)
        end)
    end)

    describe("to_table()", function()
        it("returns a plain table with all fields", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
                expires_at = 1000, metadata = { k = "v" },
            })
            local t = link:to_table()
            assert.are.equal("default", t.namespace)
            assert.are.equal("abc", t.code)
            assert.are.equal("https://example.com", t.target)
            assert.are.equal("ACTIVE", t.status)
            assert.are.equal(1000, t.expires_at)
            assert.are.equal("v", t.metadata.k)
        end)
    end)
end)

describe("ShortLink lifecycle overrides", function()
    local function new(status, rules)
        return ShortLink.new({ namespace = "ns", code = "abc", target = "https://example.com", status = status }, rules)
    end

    it("uses partial validation overrides including the default ACTIVE state", function()
        local seen = {}
        local rules = { is_valid = function(status) seen[#seen + 1] = status; return status ~= "ACTIVE" end }
        local link, err = new(nil, rules)
        assert.is_nil(link)
        assert.equal("INVALID", err)
        assert.equal("ACTIVE", seen[1])
        assert.equal("DISABLED", assert(new("DISABLED", rules)).status)
        assert.is_nil(rules.can_transition)
    end)

    it("never allows a custom validator to add persistent states", function()
        local link, err = new("EXPIRED", { is_valid = function() return true end })
        assert.is_nil(link)
        assert.equal("INVALID", err)
    end)

    it("applies custom transition rejection and skips same-state transitions", function()
        local called = 0
        local rules = { can_transition = function(from, to)
            called = called + 1
            assert.equal("ACTIVE", from)
            assert.equal("DISABLED", to)
            return false
        end }
        local original = assert(new("ACTIVE"))
        local updated, err = original:with_patch({ status = "DISABLED", target = "https://changed.com" }, rules)
        assert.is_nil(updated)
        assert.equal("INVALID", err)
        assert.equal("ACTIVE", original.status)
        assert.equal("https://example.com", original.target)
        assert.equal("ACTIVE", assert(original:with_patch({ status = "ACTIVE" }, rules)).status)
        assert.equal(1, called)
    end)

    it("blocks every mutation of a deleted entity despite permissive overrides", function()
        local deleted = assert(new("DELETED"))
        local rules = { is_valid = function() return true end, can_transition = function() return true end }
        for _, patch in ipairs({ {}, { status = "DELETED" }, { target = "https://new.com" }, { status = "ACTIVE" } }) do
            local result, err = deleted:with_patch(patch, rules)
            assert.is_nil(result)
            assert.equal("INVALID", err)
        end
    end)

    it("rejects unsupported patches and retains expiration when nil is omitted", function()
        local original = assert(new("ACTIVE"))
        for _, patch in ipairs({ { metadata = {} }, { unknown = true }, { [1] = "bad" } }) do
            local result, err = original:with_patch(patch)
            assert.is_nil(result)
            assert.equal("INVALID", err)
        end
        local expiring = assert(original:with_patch({ expires_at = 100 }))
        assert.equal(100, assert(expiring:with_patch({ expires_at = nil })).expires_at)
    end)
end)

describe("ShortLink rule call boundaries", function()
    local function data()
        return { namespace = "ns", code = "abc", target = "https://example.com" }
    end

    it("reports malformed direct rule arguments as programming errors", function()
        assert.has_error(function() ShortLink.new(data(), false) end)
        assert.has_error(function() ShortLink.new(data(), { is_valid = false }) end)
        local original = assert(ShortLink.new(data()))
        assert.has_error(function() original:with_patch({ status = "DISABLED" }, { can_transition = {} }) end)
        assert.equal(Lifecycle.ACTIVE, original.status)
    end)

    it("rejects a malformed source status even when custom transitions allow everything", function()
        local original = assert(ShortLink.new(data()))
        original.status = "UNKNOWN"
        local updated, err = original:with_patch({ status = "ACTIVE" }, { can_transition = function() return true end })
        assert.is_nil(updated)
        assert.equal("INVALID", err)
    end)
end)
