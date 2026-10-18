local helpers = require("spec.helpers")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Interactor", function()
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

        it("rejects missing target as INVALID", function()
            local value, err = svc:create({}, { code = "abc" })
            assert.is_nil(value)
            assert.equal(Errors.INVALID, err)
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
            assert.are.equal("DELETED", result.status)
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
            assert.are.equal(Errors.INVALID, err)
        end)
    end)

    describe("resolve() — repository outcomes", function()
        for _, outcome in ipairs({ Errors.NOT_FOUND, "connection refused" }) do
            it("distinguishes " .. outcome .. " from other outcomes", function()
                local another, repo = helpers.fixture()
                repo.get = function() return nil, outcome end
                local result, err = another:resolve({}, Identity.new("anything"))
                if outcome == Errors.NOT_FOUND then
                    assert.is_nil(err)
                    assert.is_false(result.found)
                    assert.is_false(result.resolvable)
                else
                    assert.is_nil(result)
                    assert.equal("connection refused", err)
                end
            end)
        end
        it("rejects missing error rather than treating it as NOT_FOUND", function()
            local another, repo = helpers.fixture()
            repo.get = function() return nil, nil end
            assert.has_error(function() another:resolve({}, Identity.new("anything")) end)
        end)
    end)

    describe("resolve with expiration", function()
        it("returns EXPIRED for expired link", function()
            -- Use a fixture with a specific clock time
            local svc2 = helpers.fixture({ clock = helpers.fake_clock(2000) })
            svc2:create({}, { code = "exp", target = "https://x.com", expires_at = 1000 })
            local result = svc2:resolve({}, Identity.new("default", "exp"))
            assert.is_true(result.found)
            assert.are.equal("EXPIRED", result.status)
            assert.is_nil(result.target)
        end)
    end)
    for _, operation in ipairs({ "create", "resolve", "update", "delete" }) do
        it("dispatches general and specific phases around the actual " .. operation, function()
            local slds = require("slds")
            local hooks, order, observed, ctx = slds.Hooks.new(), {}, {}, {}
            local function record(label)
                return function(received_ctx, point)
                    order[#order + 1] = label
                    observed[#observed + 1] = { same_ctx = rawequal(ctx, received_ctx), point = point }
                end
            end
            local before, after = "before_" .. operation, "after_" .. operation
            hooks:on(slds.HookPoint.AFTER, record("general-after-A"))
                :on(after, record("specific-after"))
                :on(before, record("specific-before-A"))
                :on(slds.HookPoint.BEFORE, record("general-before"))
                :on(before, record("specific-before-B"))
                :on(slds.HookPoint.AFTER, record("general-after-B"))
            local interactor, repo = helpers.fixture({ hooks = hooks })
            local id = Identity.new("one")
            if operation ~= "create" then
                assert(repo:create(ctx, assert(slds.ShortLink.new({
                    namespace = id.namespace, code = id.code, target = "https://example.com",
                }))))
            end
            local method = operation == "resolve" and "get" or operation
            local execute = repo[method]
            repo[method] = function(self, ...)
                order[#order + 1] = "operation"
                return execute(self, ...)
            end
            if operation == "create" then
                assert(interactor:create(ctx, { code = "one", target = "https://example.com" }))
            else
                assert(interactor[operation](interactor, ctx, id, { target = "https://example.org" }))
            end
            assert.same({ "general-before", "specific-before-A", "specific-before-B", "operation",
                "specific-after", "general-after-A", "general-after-B" }, order)
            for index, value in ipairs(observed) do
                assert.is_true(value.same_ctx)
                assert.equal(index <= 3 and before or after, value.point)
            end
        end)
    end

end)
