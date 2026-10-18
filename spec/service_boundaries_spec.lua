local helpers = require("spec.helpers")
local Service = require("slds.service")
local Identity = require("slds.domain.identity")
local Errors = require("slds.domain.errors")

describe("Service boundaries", function()
    it("rejects missing ports, invalid options, and invalid clock configuration", function()
        assert.has_error(function() Service.new(false) end)
        local _, repo, gen, enc = helpers.fixture()
        for _, field in ipairs({ "repository", "generator", "encoder", "clock" }) do
            local opts = { repository = repo, generator = gen, encoder = enc }
            opts[field] = false
            assert.has_error(function() Service.new(opts) end)
        end
    end)

    it("validates operation containers and identity fields before accessing ports", function()
        local svc = helpers.fixture()
        assert.has_error(function() svc:create({}, false) end)
        assert.has_error(function() svc:create({}, { target = "https://x.com", code = false }) end)
        assert.has_error(function() svc:create({}, { target = "https://x.com", namespace = false }) end)
        for _, operation in ipairs({ "resolve", "update", "delete" }) do
            assert.has_error(function() svc[operation](svc, false, Identity.new("abc"), {}) end)
            assert.has_error(function() svc[operation](svc, {}, false, {}) end)
            assert.has_error(function() svc[operation](svc, {}, {}, {}) end)
            assert.has_error(function() svc[operation](svc, {}, { namespace = "ns", code = false }, {}) end)
        end
        assert.has_error(function() svc:update({}, Identity.new("abc"), false) end)
    end)

    it("reports generation failures and skips successful after callbacks", function()
        local after = false
        local svc = helpers.fixture({ generator = { generate = function() return nil, "offline" end } })
        svc:use({ after_create = function() after = true end })
        local link, err = svc:create({}, { target = "https://x.com" })
        assert.is_nil(link)
        assert.equal("generator: offline", err)
        assert.is_false(after)
    end)

    it("rejects invalid encoder output and preserves empty-code generation behavior", function()
        for _, output in ipairs({ false, "", 123 }) do
            local svc = helpers.fixture({ encoder = { encode = function() return output end } })
            local link, err = svc:create({}, { target = "https://x.com" })
            assert.is_nil(link)
            assert.equal("encoder: produced empty code", err)
        end
        local svc = helpers.fixture()
        assert.equal("1", svc:create({}, { target = "https://x.com", code = "" }).code)
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

    it("returns domain and repository failures without firing success hooks", function()
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
        assert.is_false(fired)
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
        assert.is_false(updated_after)
        assert.equal("https://old.com", svc:resolve({}, id).target)
    end)

    it("propagates deletion failures without firing successful after_delete", function()
        local svc, repo = helpers.fixture()
        svc:create({}, { code = "abc", target = "https://x.com" })
        local deleted_after = false
        svc:use({ after_delete = function() deleted_after = true end })
        repo.delete = function() return nil, "delete failed" end
        local ok, err = svc:delete({}, Identity.new("abc"))
        assert.is_nil(ok)
        assert.equal("delete failed", err)
        assert.is_false(deleted_after)
        assert.equal("ACTIVE", svc:resolve({}, Identity.new("abc")).status)
    end)

    it("preserves legacy missing results for update and delete", function()
        local svc = helpers.fixture({ repository = { get = function() return nil end } })
        for _, operation in ipairs({ "update", "delete" }) do
            local result, err = svc[operation](svc, {}, Identity.new("missing"), {})
            assert.is_nil(result)
            assert.equal(Errors.NOT_FOUND, err)
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
        assert.equal("ACTIVE", svc:resolve({}, id).status)
        svc:update({}, id, { expires_at = 1000 })
        assert.equal("EXPIRED", svc:resolve({}, id).status)
        assert.equal("ACTIVE", repo:get({}, id).status)
        svc:update({}, id, { status = "DISABLED" })
        assert.equal("DISABLED", svc:resolve({}, id).status)
        svc:delete({}, id)
        assert.equal("DELETED", svc:resolve({}, id).status)
    end)

    it("does not call after_resolve when the repository fails", function()
        local svc = helpers.fixture({ repository = { get = function() return nil, "offline" end } })
        local fired = false
        svc:use({ after_resolve = function() fired = true end })
        local result, err = svc:resolve({}, Identity.new("abc"))
        assert.is_nil(result)
        assert.equal("offline", err)
        assert.is_false(fired)
    end)
end)
