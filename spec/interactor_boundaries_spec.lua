local helpers = require("spec.helpers")
local Interactor = require("slds.interactor")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Interactor boundaries", function()
    it("rejects missing ports, invalid options, and invalid clock configuration", function()
        assert.has_error(function() Interactor.new(false) end)
        local _, repo, gen = helpers.fixture()
        for _, field in ipairs({ "repository", "code_generator", "clock", "hooks", "lifecycle" }) do
            local opts = { repository = repo, code_generator = gen }
            opts[field] = false
            assert.has_error(function() Interactor.new(opts) end)
        end
    end)

    it("validates operation containers and identity fields before accessing ports", function()
        local svc = helpers.fixture()
        assert.has_error(function() svc:create({}, false) end)
        local value, err = svc:create({}, { target = "https://x.com", code = false })
        assert.is_nil(value)
        assert.equal(Errors.INVALID, err)
        value, err = svc:create({}, { target = "https://x.com", namespace = false })
        assert.is_nil(value)
        assert.equal(Errors.INVALID, err)
        for _, operation in ipairs({ "resolve", "update", "delete" }) do
            assert.has_error(function() svc[operation](svc, false, Identity.new("abc"), {}) end)
            assert.has_error(function() svc[operation](svc, {}, false, {}) end)
            assert.has_error(function() svc[operation](svc, {}, {}, {}) end)
            assert.has_error(function() svc[operation](svc, {}, { namespace = "ns", code = false }, {}) end)
        end
        assert.has_error(function() svc:update({}, Identity.new("abc"), false) end)
    end)

    it("observes generation failures through AFTER callbacks", function()
        local after = false
        local svc = helpers.fixture({ generator = { generate = function() return nil, "offline" end } })
        svc:use({ after_create = function() after = true end })
        local link, err = svc:create({}, { target = "https://x.com" })
        assert.is_nil(link)
        assert.equal("offline", err)
        assert.is_true(after)
    end)

    it("rejects invalid encoder output and explicit empty codes", function()
        for _, output in ipairs({ false, "", 123 }) do
            local svc = helpers.fixture({ encoder = { encode = function() return output end } })
            local link, err = svc:create({}, { target = "https://x.com" })
            assert.is_nil(link)
            assert.equal(Errors.INVALID, err)
        end
        local svc = helpers.fixture()
        local value, err = svc:create({}, { target = "https://x.com", code = "" })
        assert.is_nil(value)
        assert.equal(Errors.INVALID, err)
    end)

    it("keeps opaque string IDs and adapter-specific code lengths", function()
        local svc = helpers.fixture({
            generator = { generate = function() return "opaque:identifier" end },
            encoder = { encode = function(_, id)
                assert.equal("opaque:identifier", id)
                return "validCodeLongerThanTenCharacters"
            end },
        })
        local created = assert(svc:create({}, { target = "https://x.com" }))
        assert.equal("validCodeLongerThanTenCharacters", created.code)
        assert.equal("https://x.com", svc:resolve({}, Identity.new(created.code)).target)
    end)

    it("observes domain and repository failures through AFTER callbacks", function()
        local svc, repo = helpers.fixture()
        local fired = false
        svc:use({ after_create = function() fired = true end })
        local invalid, err = svc:create({}, { code = "invalid", target = "data:bad" })
        assert.is_nil(invalid)
        assert.matches("^INVALID", err)
        repo.create = function() return nil, "write failed" end
        local failed, write_err = svc:create({}, { code = "abc", target = "https://x.com" })
        assert.is_nil(failed)
        assert.equal("write failed", write_err)
        assert.is_true(fired)
    end)

    it("does not persist invalid updates and propagates failed commits", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://old.com" })
        local id = Identity.new("abc")
        local invalid, err = svc:update({}, id, { target = "file:bad" })
        assert.is_nil(invalid)
        assert.matches("^INVALID", err)
        local updated_after = false
        svc:use({ after_update = function() updated_after = true end })
        repo.update = function() return nil, "update failed" end
        local failed, update_err = svc:update({}, id, { target = "https://new.com" })
        assert.is_nil(failed)
        assert.equal("update failed", update_err)
        assert.is_true(updated_after)
        assert.equal("https://old.com", svc:resolve({}, id).target)
    end)

    it("observes deletion failures through AFTER callbacks", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://x.com" })
        local deleted_after = false
        svc:use({ after_delete = function() deleted_after = true end })
        repo.delete = function() return nil, "delete failed" end
        local ok, err = svc:delete({}, Identity.new("abc"))
        assert.is_nil(ok)
        assert.equal("delete failed", err)
        assert.is_true(deleted_after)
        assert.equal("ACTIVE", svc:resolve({}, Identity.new("abc")).status)
    end)

    it("rejects missing result/error pairs for update and delete", function()
        local svc, repo = helpers.fixture()
        for _, operation in ipairs({ "update", "delete" }) do
            repo[operation] = function() return nil, nil end
            assert.has_error(function() svc[operation](svc, {}, Identity.new("missing"), {}) end)
        end
    end)

    it("rejects invalid clock output and retains equality and status precedence", function()
        for _, value in ipairs({ false, "2000", 0/0, math.huge, -math.huge }) do
            local svc = helpers.fixture({ clock = function() return value end })
            svc:create({}, { code = "abc", target = "https://x.com" })
            assert.has_error(function() svc:resolve({}, Identity.new("abc")) end)
        end
        local svc, repo = helpers.fixture({ clock = helpers.fake_clock(2000) })
        local id = Identity.new("abc")
        svc:create({}, { code = "abc", target = "https://x.com", expires_at = 2000 })
        assert.equal("EXPIRED", svc:resolve({}, id).status)
        svc:update({}, id, { expires_at = 1000 })
        assert.equal("EXPIRED", svc:resolve({}, id).status)
        assert.equal("ACTIVE", repo:get({}, id).status)
        svc:update({}, id, { status = "DISABLED" })
        assert.equal("DISABLED", svc:resolve({}, id).status)
        svc:delete({}, id)
        assert.equal("DELETED", svc:resolve({}, id).status)
    end)

    it("calls after_resolve when the repository fails", function()
        local svc, repo = helpers.fixture()
        repo.get = function() return nil, "offline" end
        local fired = false
        svc:use({ after_resolve = function() fired = true end })
        local result, err = svc:resolve({}, Identity.new("abc"))
        assert.is_nil(result)
        assert.equal("offline", err)
        assert.is_true(fired)
    end)
end)


describe("Interactor dependency shapes", function()
    it("requires complete repository, code generator and hook methods", function()
        for _, name in ipairs({ "create", "get", "update", "delete" }) do
            local _, repo = helpers.fixture()
            repo[name] = false
            assert.has_error(function() Interactor.new({ repository = repo }) end)
        end
        local _, repo = helpers.fixture()
        assert.has_error(function() Interactor.new({ repository = repo, code_generator = {} }) end)
        assert.has_error(function() Interactor.new({ repository = repo, hooks = {} }) end)
    end)

    it("rejects invalid record and deletion success responses", function()
        for _, operation in ipairs({ "create", "update", "resolve", "delete" }) do
            local svc, repo = helpers.fixture()
            local method = operation == "resolve" and "get" or operation
            local function invoke()
                if operation == "create" then
                    return svc:create({}, { code = "one", target = "https://x.com" })
                end
                return svc[operation](svc, {}, Identity.new("one"), {})
            end
            for _, bad in ipairs({ false, 42, "record" }) do
                repo[method] = function() return bad end
                assert.has_error(invoke)
            end
            repo[method] = function() return {}, "offline" end
            assert.has_error(invoke)
        end
    end)
end)
