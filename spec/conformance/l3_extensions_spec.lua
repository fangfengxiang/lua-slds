-- L3 Extensions Conformance Tests
-- SLDS L3: events/hooks, cache, metadata, multi-tenant.

local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Conformance L3 — Extensions", function()
    describe("metadata_preserved", function()
        it("metadata field stored and retrieved without interpretation", function()
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
            svc:create({}, { code = "nometa", target = "https://x.com" })
            local link = svc.repository:get({}, Identity.new("default", "nometa"))
            assert.is_nil(link.metadata)
        end)
    end)

    describe("metadata_not_interpreted", function()
        it("Core MUST NOT expose metadata fields as domain properties", function()
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
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
            local svc = helpers.fixture()
            svc:use({
                before_create = function() error("boom") end,
            })
            local link, err = svc:create({}, { code = "isolated", target = "https://x.com" })
            assert.is_nil(err)
            assert.is_truthy(link)
        end)

        it("hook failure does not break resolve operation", function()
            local svc = helpers.fixture()
            svc:create({}, { code = "isolated", target = "https://x.com" })
            svc:use({
                before_resolve = function() error("boom") end,
            })
            local result = svc:resolve({}, Identity.new("default", "isolated"))
            assert.is_true(result.found)
        end)
    end)

    describe("tenant_aware", function()
        it("repository can use ctx for tenant-aware operations", function()
            local svc = helpers.fixture()
            -- Create in default namespace
            svc:create({ tenant = "acme" }, { code = "shared", target = "https://acme.com" })
            -- Resolve should work
            local result = svc:resolve({ tenant = "acme" }, Identity.new("default", "shared"))
            assert.is_true(result.found)
            assert.are.equal("https://acme.com", result.target)
        end)

        it("different namespaces are isolated", function()
            local svc = helpers.fixture()
            svc:create({}, { namespace = "ns1", code = "same", target = "https://ns1.com" })
            svc:create({}, { namespace = "ns2", code = "same", target = "https://ns2.com" })
            local r1 = svc:resolve({}, Identity.new("ns1", "same"))
            local r2 = svc:resolve({}, Identity.new("ns2", "same"))
            assert.are.equal("https://ns1.com", r1.target)
            assert.are.equal("https://ns2.com", r2.target)
        end)
    end)

    describe("cache_not_source_of_truth", function()
        -- Core 不缓存——Repository 是唯一真相源
        -- Core does not cache — Repository is the single source of truth
        it("resolve always reads from repository, not a stale cache", function()
            local svc = helpers.fixture()
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

        it("resolve after delete reflects deleted state, not stale cache", function()
            local svc = helpers.fixture()
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

        it("resolve after disable reflects disabled state, not stale cache", function()
            local svc = helpers.fixture()
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
            local Service = require("slds.service")
            local svc = Service.new({
                repository = broken_repo,
                generator  = helpers.mock_generator(),
                encoder    = helpers.mock_encoder(),
                clock      = helpers.fake_clock(1000000),
            })
            local result, err = svc:resolve({}, Identity.new("default", "anything"))
            assert.is_nil(result)
            assert.are.equal("connection refused", err)
        end)
    end)
end)
