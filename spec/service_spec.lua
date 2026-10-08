local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Service", function()
    local svc

    before_each(function()
        svc = helpers.fixture()
    end)

    describe("create()", function()
        it("creates with generated code", function()
            local link, err = svc:create({}, { target = "https://example.com" })
            assert.is_nil(err)
            assert.is_truthy(link)
            assert.is_truthy(link.code)
            assert.are.equal("https://example.com", link.target)
            assert.are.equal("ACTIVE", link.status)
        end)

        it("creates with custom code", function()
            local link, err = svc:create({}, { code = "custom", target = "https://x.com" })
            assert.is_nil(err)
            assert.are.equal("custom", link.code)
        end)

        it("creates with namespace", function()
            local link = svc:create({}, { namespace = "marketing", code = "camp1", target = "https://x.com" })
            assert.are.equal("marketing", link.namespace)
        end)

        it("creates with expires_at", function()
            local link = svc:create({}, { code = "exp", target = "https://x.com", expires_at = 2000 })
            assert.are.equal(2000, link.expires_at)
        end)

        it("returns CONFLICT on duplicate code", function()
            svc:create({}, { code = "dup", target = "https://x.com" })
            local link, err = svc:create({}, { code = "dup", target = "https://y.com" })
            assert.is_nil(link)
            assert.are.equal(Errors.CONFLICT, err)
        end)

        it("errors on missing target", function()
            assert.has_error(function()
                svc:create({}, { code = "abc" })
            end)
        end)

        it("errors on non-table ctx", function()
            assert.has_error(function()
                svc:create("not-table", { target = "https://x.com" })
            end)
        end)
    end)

    describe("resolve()", function()
        it("resolves an active link", function()
            local link = svc:create({}, { code = "abc", target = "https://example.com" })
            local result = svc:resolve({}, Identity.new("default", "abc"))
            assert.is_true(result.found)
            assert.are.equal("https://example.com", result.target)
            assert.are.equal("ACTIVE", result.status)
        end)

        it("returns found=false for non-existent identity", function()
            local result = svc:resolve({}, Identity.new("default", "nonexistent"))
            assert.is_false(result.found)
            assert.are.equal(Errors.NOT_FOUND, result.status)
        end)
    end)

    describe("update()", function()
        it("updates target", function()
            svc:create({}, { code = "abc", target = "https://old.com" })
            local updated = svc:update({}, Identity.new("default", "abc"), { target = "https://new.com" })
            assert.are.equal("https://new.com", updated.target)
        end)

        it("updates status ACTIVE → DISABLED", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            local updated = svc:update({}, Identity.new("default", "abc"), { status = "DISABLED" })
            assert.are.equal("DISABLED", updated.status)
        end)

        it("returns NOT_FOUND for non-existent identity", function()
            local link, err = svc:update({}, Identity.new("default", "nope"), { target = "https://x.com" })
            assert.is_nil(link)
            assert.are.equal(Errors.NOT_FOUND, err)
        end)

        it("errors on code change attempt", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            assert.has_error(function()
                svc:update({}, Identity.new("default", "abc"), { code = "xyz" })
            end)
        end)

        it("errors on namespace change attempt", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            assert.has_error(function()
                svc:update({}, Identity.new("default", "abc"), { namespace = "other" })
            end)
        end)
    end)

    describe("delete()", function()
        it("deletes an active link", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            local ok = svc:delete({}, Identity.new("default", "abc"))
            assert.is_true(ok)
        end)

        it("makes link unresolvable after delete", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            svc:delete({}, Identity.new("default", "abc"))
            local result = svc:resolve({}, Identity.new("default", "abc"))
            assert.is_true(result.found)
            assert.are.equal(Errors.DELETED, result.status)
            assert.is_nil(result.target)
        end)

        it("returns NOT_FOUND for non-existent identity", function()
            local ok, err = svc:delete({}, Identity.new("default", "nope"))
            assert.is_nil(ok)
            assert.are.equal(Errors.NOT_FOUND, err)
        end)

        it("rejects double delete", function()
            svc:create({}, { code = "abc", target = "https://x.com" })
            svc:delete({}, Identity.new("default", "abc"))
            local ok, err = svc:delete({}, Identity.new("default", "abc"))
            assert.is_nil(ok)
            assert.are.equal("already deleted", err)
        end)
    end)

    describe("resolve() — internal error propagation", function()
        it("returns nil, err when repository has internal error", function()
            local broken_repo = {
                get = function(self, ctx, identity)
                    return nil, "connection refused"
                end,
            }
            local Service = require("slds.service")
            local svc2 = Service.new({
                repository = broken_repo,
                generator  = helpers.mock_generator(),
                encoder    = helpers.mock_encoder(),
                clock      = helpers.fake_clock(1000000),
            })
            local result, err = svc2:resolve({}, Identity.new("default", "anything"))
            assert.is_nil(result)
            assert.are.equal("connection refused", err)
        end)

        it("returns not-found result for NOT_FOUND error", function()
            local notfound_repo = {
                get = function(self, ctx, identity)
                    return nil, Errors.NOT_FOUND
                end,
            }
            local Service = require("slds.service")
            local svc2 = Service.new({
                repository = notfound_repo,
                generator  = helpers.mock_generator(),
                encoder    = helpers.mock_encoder(),
                clock      = helpers.fake_clock(1000000),
            })
            local result = svc2:resolve({}, Identity.new("default", "anything"))
            assert.is_false(result.found)
            assert.are.equal(Errors.NOT_FOUND, result.status)
        end)

        it("returns not-found result for nil err (link not found)", function()
            local silent_repo = {
                get = function(self, ctx, identity)
                    return nil, nil
                end,
            }
            local Service = require("slds.service")
            local svc2 = Service.new({
                repository = silent_repo,
                generator  = helpers.mock_generator(),
                encoder    = helpers.mock_encoder(),
                clock      = helpers.fake_clock(1000000),
            })
            local result = svc2:resolve({}, Identity.new("default", "anything"))
            assert.is_false(result.found)
            assert.are.equal(Errors.NOT_FOUND, result.status)
        end)
    end)

    describe("resolve with expiration", function()
        it("returns EXPIRED for expired link", function()
            -- Use a fixture with a specific clock time
            local svc2 = helpers.fixture({ clock = helpers.fake_clock(2000) })
            svc2:create({}, { code = "exp", target = "https://x.com", expires_at = 1000 })
            local result = svc2:resolve({}, Identity.new("default", "exp"))
            assert.is_true(result.found)
            assert.are.equal(Errors.EXPIRED, result.status)
            assert.is_nil(result.target)
        end)
    end)
end)
