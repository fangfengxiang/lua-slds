-- luacheck 配置：Lua 5.1 兼容（项目目标 5.1 / LuaJIT / 5.3+）
-- 运行：luacheck src/ adapters/ spec/

std = "lua51"
max_line_length = 120

-- src/ 核心：纯 Lua
files["src/"] = {
    ignore = { "212/self" },
}

-- src/slds/ports/：接口桩方法，参数未使用是预期的
files["src/slds/ports/"] = {
    ignore = { "212" },
}

-- adapters/：适配器实现，ctx 参数可能未使用
files["adapters/"] = {
    ignore = { "212/self", "212/ctx" },
}

-- spec/：busted BDD 测试文件
files["spec/"] = {
    globals = {
        "describe", "it", "before_each", "after_each",
        "assert", "pending", "spy", "stub", "mock",
        "context", "setup", "teardown", "finally",
    },
    ignore = { "211", "212", "213", "221", "311", "143" },
}

exclude_files = {
    "docs/",
    "openspec/",
    ".codebuddy/",
}
