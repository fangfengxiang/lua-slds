package = "lua-slds"
version = "scm-1"

source = {
   url = "git+https://github.com/fangfengxiang/lua-slds.git",
   branch = "main",
}

description = {
   summary = "Short Link Domain Specification — a pure Lua domain library for short link identity, lifecycle, and resolution semantics.",
   detailed = [[
      SLDS (Short Link Domain Specification) defines the identity, lifecycle,
      and resolution semantics of short links, independent of transport,
      storage, caching, and security policy.

      Core layer has zero external dependencies (no ngx/redis/mysql/cjson),
      using only pure Lua 5.1/5.3/LuaJIT compatible syntax. Infrastructure
      adapters (Redis/MySQL/OpenResty) are pluggable via hexagonal ports.

      Features:
        - Identity value object {namespace, code}
        - ShortLink domain entity with lifecycle (ACTIVE/DISABLED/DELETED)
        - Resolution as first-class domain operation (not Repository.get alias)
        - Ports: Repository, Generator, Encoder (hexagonal architecture)
        - Hooks extension mechanism (Logger/Metrics/Tracer via pcall isolation)
        - Conformance Test Suite L0-L3
   ]],
   homepage = "https://github.com/fangfengxiang/lua-slds",
   license = "Apache-2.0",
   labels = { "short-link", "domain", "lua", "specification", "hexagonal" },
   maintainer = "Frank Zhang <fangfengxiang@gmail.com>",
}

dependencies = {
   -- Core has zero runtime dependencies — pure Lua only.
}

build = {
   type = "builtin",
   modules = {
      ["slds"]                           = "src/slds/init.lua",
      ["slds.service"]                   = "src/slds/service.lua",
      ["slds.hooks"]                     = "src/slds/hooks.lua",
      ["slds.domain.identity"]           = "src/slds/domain/identity.lua",
      ["slds.domain.short_link"]         = "src/slds/domain/short_link.lua",
      ["slds.domain.lifecycle"]          = "src/slds/domain/lifecycle.lua",
      ["slds.domain.resolution"]         = "src/slds/domain/resolution.lua",
      ["slds.domain.errors"]             = "src/slds/domain/errors.lua",
      ["slds.ports.repository"]          = "src/slds/ports/repository.lua",
      ["slds.ports.generator"]           = "src/slds/ports/generator.lua",
      ["slds.ports.encoder"]             = "src/slds/ports/encoder.lua",
      ["slds.adapters.inmemory.repository"]   = "adapters/inmemory/repository.lua",
      ["slds.adapters.sequential.generator"]  = "adapters/sequential/generator.lua",
      ["slds.adapters.base62.encoder"]        = "adapters/base62/encoder.lua",
   },
   copy_directories = { "docs", "spec" },
}

test_dependencies = {
   "busted >= 2.0.0",
   "luacheck >= 1.0.0",
   "luacov >= 0.15.0",
}
