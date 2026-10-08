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

    describe("is_resolvable(now)", function()
        it("returns true for ACTIVE and not expired", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
            })
            assert.is_true(link:is_resolvable(1000))
        end)

        it("returns false for DISABLED", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "DISABLED",
            })
            assert.is_false(link:is_resolvable(1000))
        end)

        it("returns false for DELETED", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "DELETED",
            })
            assert.is_false(link:is_resolvable(1000))
        end)

        it("returns false for expired ACTIVE", function()
            local link = ShortLink.new({
                namespace = "default", code = "abc",
                target = "https://example.com", status = "ACTIVE",
                expires_at = 500,
            })
            assert.is_false(link:is_resolvable(1000))
        end)
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
            assert.has_error(function()
                link:with_patch({ status = "ACTIVE" })
            end)
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
