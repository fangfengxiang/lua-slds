-- L3 Extensions Conformance Tests
-- SLDS L3: metadata, hooks, context propagation, and repository visibility.

local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

local busted = require("busted")
local describe, it = busted.describe, busted.it
local assert = require("luassert")

return function(make_fixture)
describe("Conformance L3 — Extensions", function()
    describe("metadata_preserved", function()
        it("metadata field stored and retrieved without interpretation", function()
            local svc = make_fixture()
            svc:create({}, {
                code = "meta",
                target = "https://x.com",
                metadata = { campaign = "bf", owner = "mkt" },
            })
            local result = svc:resolve({}, Identity.new("default", "meta"))
            assert.is_true(result.found)
            -- Metadata is not part of ResolutionResult but can be checked via repository
            local link = svc.repository:get({}, Identity.new("default", "meta"))
            assert.are.equal("bf", link.metadata.campaign)
            assert.are.equal("mkt", link.metadata.owner)
        end)

        it("no metadata field — metadata is nil", function()
            local svc = make_fixture()
            svc:create({}, { code = "nometa", target = "https://x.com" })
            local link = svc.repository:get({}, Identity.new("default", "nometa"))
            assert.is_nil(link.metadata)
        end)
    end)

    describe("metadata_not_interpreted", function()
        it("Core MUST NOT expose metadata fields as domain properties", function()
            local svc = make_fixture()
            local link = svc:create({}, {
                code = "meta2",
                target = "https://x.com",
                metadata = { custom_field = "value" },
            })
            -- link should not have a custom_field directly
            assert.is_nil(link.custom_field)
            -- link.metadata should contain it
            assert.are.equal("value", link.metadata.custom_field)
        end)
    end)

    describe("hook_before_after", function()
        it("hooks fire before and after create", function()
            local svc = make_fixture()
            local fired = {}
            svc:use({
                before_create = function(ctx, input)
                    table.insert(fired, "before_create")
                end,
                after_create = function(ctx, link)
                    table.insert(fired, "after_create")
                end,
            })
            svc:create({}, { code = "hooked", target = "https://x.com" })
            assert.are.same({ "before_create", "after_create" }, fired)
        end)

        it("hooks fire before and after resolve", function()
            local svc = make_fixture()
            local fired = {}
            svc:create({}, { code = "hooked", target = "https://x.com" })
            svc:use({
                before_resolve = function(ctx, identity)
                    table.insert(fired, "before_resolve")
                end,
                after_resolve = function(ctx, result)
                    table.insert(fired, "after_resolve")
                end,
            })
            svc:resolve({}, Identity.new("default", "hooked"))
            assert.are.same({ "before_resolve", "after_resolve" }, fired)
        end)

        it("hooks fire before and after update", function()
            local svc = make_fixture()
            local fired = {}
            svc:create({}, { code = "hooked", target = "https://x.com" })
            svc:use({
                before_update = function(ctx, identity, patch)
                    table.insert(fired, "before_update")
                end,
                after_update = function(ctx, link)
                    table.insert(fired, "after_update")
                end,
            })
            svc:update({}, Identity.new("default", "hooked"), { target = "https://y.com" })
            assert.are.same({ "before_update", "after_update" }, fired)
        end)

        it("hooks fire before and after delete", function()
            local svc = make_fixture()
            local fired = {}
            svc:create({}, { code = "hooked", target = "https://x.com" })
            svc:use({
                before_delete = function(ctx, identity)
                    table.insert(fired, "before_delete")
                end,
                after_delete = function(ctx)
                    table.insert(fired, "after_delete")
                end,
            })
            svc:delete({}, Identity.new("default", "hooked"))
            assert.are.same({ "before_delete", "after_delete" }, fired)
        end)
    end)

    describe("hook_error_isolation", function()
        it("hook failure does not break create operation", function()
            local svc = make_fixture()
            svc:use({
                before_create = function() error("boom") end,
            })
            local link, err = svc:create({}, { code = "isolated", target = "https://x.com" })
            assert.is_nil(err)
            assert.is_truthy(link)
        end)

        it("hook failure does not break resolve operation", function()
            local svc = make_fixture()
            svc:create({}, { code = "isolated", target = "https://x.com" })
            svc:use({
                before_resolve = function() error("boom") end,
            })
            local result = svc:resolve({}, Identity.new("default", "isolated"))
            assert.is_true(result.found)
        end)
    end)

    describe("context_and_namespace", function()
        it("forwards the same opaque context to generation and repository operations", function()
            local svc, repo, gen = make_fixture()
            local ctx, called = { trace = {} }, {}
            for _, method in ipairs({ "create", "get", "update", "delete" }) do
                local original = repo[method]
                repo[method] = function(self, received, ...)
                    assert.is_true(rawequal(ctx, received))
                    called[method] = true
                    return original(self, received, ...)
                end
            end
            local generate = gen.generate
            gen.generate = function(self, received)
                assert.is_true(rawequal(ctx, received))
                called.generate = true
                return generate(self, received)
            end
            local link = assert(svc:create(ctx, { target = "https://x.com" }))
            local id = Identity.new(link.namespace, link.code)
            assert(svc:resolve(ctx, id))
            assert(svc:update(ctx, id, { target = "https://new.com" }))
            assert(svc:delete(ctx, id))
            for _, method in ipairs({ "generate", "create", "get", "update", "delete" }) do
                assert.is_true(called[method])
            end
        end)

        it("context is accepted without claiming tenant isolation", function()
            local svc = make_fixture()
            -- Create in default namespace
            svc:create({ tenant = "acme" }, { code = "shared", target = "https://acme.com" })
            -- Resolve should work
            local result = svc:resolve({ tenant = "acme" }, Identity.new("default", "shared"))
            assert.is_true(result.found)
            assert.are.equal("https://acme.com", result.target)
        end)

        it("different namespaces are isolated", function()
            local svc = make_fixture()
            svc:create({}, { namespace = "ns1", code = "same", target = "https://ns1.com" })
            svc:create({}, { namespace = "ns2", code = "same", target = "https://ns2.com" })
            local r1 = svc:resolve({}, Identity.new("ns1", "same"))
            local r2 = svc:resolve({}, Identity.new("ns2", "same"))
            assert.are.equal("https://ns1.com", r1.target)
            assert.are.equal("https://ns2.com", r2.target)
        end)
    end)

    describe("repository_visibility", function()
        -- Core 不缓存——Repository 是唯一真相源
        -- Core does not cache — Repository is the single source of truth
        it("resolve reflects a committed target update", function()
            local svc = make_fixture()
            svc:create({}, { code = "cache1", target = "https://v1.com" })
            -- First resolve
            local r1 = svc:resolve({}, Identity.new("default", "cache1"))
            assert.are.equal("https://v1.com", r1.target)
            -- Update target
            svc:update({}, Identity.new("default", "cache1"), { target = "https://v2.com" })
            -- Second resolve must reflect the update, not a stale value
            local r2 = svc:resolve({}, Identity.new("default", "cache1"))
            assert.are.equal("https://v2.com", r2.target)
        end)

        it("resolve reflects a committed deletion", function()
            local svc = make_fixture()
            svc:create({}, { code = "cache2", target = "https://x.com" })
            -- First resolve — active
            local r1 = svc:resolve({}, Identity.new("default", "cache2"))
            assert.are.equal("ACTIVE", r1.status)
            -- Delete
            svc:delete({}, Identity.new("default", "cache2"))
            -- Second resolve must reflect DELETED, not stale ACTIVE
            local r2 = svc:resolve({}, Identity.new("default", "cache2"))
            assert.are.equal(Errors.DELETED, r2.status)
            assert.is_nil(r2.target)
        end)

        it("resolve reflects a committed disable", function()
            local svc = make_fixture()
            svc:create({}, { code = "cache3", target = "https://x.com" })
            -- First resolve — active
            local r1 = svc:resolve({}, Identity.new("default", "cache3"))
            assert.are.equal("ACTIVE", r1.status)
            -- Disable
            svc:update({}, Identity.new("default", "cache3"), { status = "DISABLED" })
            -- Second resolve must reflect DISABLED, not stale ACTIVE
            local r2 = svc:resolve({}, Identity.new("default", "cache3"))
            assert.are.equal(Errors.DISABLED, r2.status)
            assert.is_nil(r2.target)
        end)
    end)

    describe("resolve_internal_error", function()
        -- 仓库内部错误（非 NOT_FOUND）应透传给调用方
        -- Repository internal errors (non-NOT_FOUND) should propagate to caller
        it("resolve returns nil, err when repository has internal error", function()
            -- 构造一个会返回内部错误的 mock repository
            local broken_repo = {
                get = function(self, ctx, identity)
                    return nil, "connection refused"
                end,
            }
            local svc = make_fixture({ repository = broken_repo })
            local result, err = svc:resolve({}, Identity.new("default", "anything"))
            assert.is_nil(result)
            assert.are.equal("connection refused", err)
        end)
    end)
end)

describe("Conformance L3 — Port boundaries", function()
    it("isolates input, result, export, and storage metadata", function()
        local svc, repo = make_fixture()
        local metadata = { nested = { owner = "original" } }
        local link = svc:create({}, { code = "abc", target = "https://old.com", metadata = metadata })
        metadata.nested.owner = "input"
        link.metadata.nested.owner = "result"
        link.code = "renamed"
        local id = Identity.new("abc")
        local first = assert(repo:get({}, id))
        assert.equal("original", first.metadata.nested.owner)
        first:to_table().metadata.nested.owner = "export"
        local updated = assert(repo:update({}, id, { target = "https://new.com" }))
        updated.metadata.nested.owner = "update-result"
        first.metadata.nested.owner = "read-result"
        assert.equal("original", repo:get({}, id).metadata.nested.owner)
        assert.is_nil(repo:get({}, Identity.new("renamed")))
    end)
end)
end
