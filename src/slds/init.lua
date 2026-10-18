-- Public domain API. Infrastructure is assembled by the host.
local Interactor = require("slds.interactor")
local _M = {}
_M.VERSION = "0.1.1"
_M.Interactor = Interactor
_M.Identity = require("slds.domain.identity")
_M.ShortLink = require("slds.domain.short_link")
_M.Lifecycle = require("slds.domain.lifecycle")
_M.Resolution = require("slds.domain.resolution")
_M.Errors = require("slds.domain.errors")
_M.Hooks = require("slds.hooks")
_M.HookPoint = require("slds.hook_point")

function _M.new(opts)
    return Interactor.new(opts)
end

return _M
