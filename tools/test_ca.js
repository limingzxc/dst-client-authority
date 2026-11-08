const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'client_authority', 'modmain.lua'), 'utf8');

const harness = `
local CFG = { enabled = true, force_predict = true, no_pause = true, slack = 2.0, log = false }
function GetModConfigData(k) return CFG[k] end
TheNet = { GetIsServer = function() return true end }
local HANDLER = nil
function AddModRPCHandler(ns, name, fn) HANDLER = fn end
function GetModRPC(ns, name) return "rpc" end
function AddComponentPostInit() end
function AddPlayerPostInit() end
function AddGamePostInit() end
TheWorld = nil
ThePlayer = nil
function distsq(x1, z1, x2, z2) local dx, dz = x1 - x2, z1 - z2; return dx * dx + dz * dz end

local NOW = 0
function GetTime() return NOW end

;(function()
${SRC}
end)()

local function mk(x, z, o)
    o = o or {}
    local p = { x = x, y = 0, z = z, tags = o.tags or {} }
    p.Transform = {
        GetWorldPosition = function() return p.x, p.y, p.z end,
        SetPosition = function(_, nx, ny, nz) p.x = nx; p.z = nz end,
    }
    p.IsValid = function() return true end
    p.HasTag = function(self, t) return self.tags[t] == true end
    p.components = {
        locomotor = { GetWalkSpeed = function() return o.speed or 6 end },
    }
    p.entity = { CanPredictMovement = function() return o.can_predict ~= false end }
    if o.moving == false then
        p.sg = { HasStateTag = function() return false end }
    else
        p.sg = { HasStateTag = function(_, t) return t == "moving" end }
    end
    return p
end

local fails = 0
local function eq(got, want, msg)
    if math.abs(got - want) >= 0.0001 then
        fails = fails + 1
        print(string.format("FAIL  %-36s want=[%.3f] got=[%.3f]", msg, want, got))
    else
        print(string.format("ok    %-36s %.3f", msg, got))
    end
end

-- 1 首包原地：不移动
local p = mk(10, 10)
NOW = 0
HANDLER(p, 1, 10, 0, 10)
eq(p.x, 10, "first packet, no move")

-- 2 正常步进 0.2 @33ms
NOW = 0.033
HANDLER(p, 2, 10.2, 0, 10)
eq(p.x, 10.2, "normal step 0.2 accepted")

-- 3 掉帧：0.5 格 @50ms，时间基准下应当放行
p = mk(0, 0)
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.05
HANDLER(p, 2, 0.5, 0, 0)
eq(p.x, 0.5, "frame drop 0.5@50ms accepted")

-- 4 超速：0.7 格 @33ms，超出 0.396
p = mk(0, 0)
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.033
HANDLER(p, 2, 0.7, 0, 0)
eq(p.x, 0, "overspeed 0.7@33ms rejected")

-- 5 重复序列号
p = mk(0, 0)
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.033
HANDLER(p, 2, 0.2, 0, 0)
NOW = 0.066
HANDLER(p, 2, 0.9, 0, 0)
eq(p.x, 0.2, "duplicate seq ignored")

-- 6 序列号倒退
p = mk(0, 0)
NOW = 0
HANDLER(p, 5, 0, 0, 0)
NOW = 0.033
HANDLER(p, 3, 0.9, 0, 0)
eq(p.x, 0, "stale seq ignored")

-- 7 传送：服务端跳到 50，客户端还在 10 -> 静默窗口
p = mk(10, 10, { moving = false })
NOW = 0
HANDLER(p, 1, 10, 0, 10)
p.x, p.z = 50, 50
NOW = 0.033
HANDLER(p, 2, 10, 0, 10)
eq(p.x, 50, "teleport: stale report rejected")
NOW = 0.05
HANDLER(p, 3, 10, 0, 10)
eq(p.x, 50, "teleport: still inside window")

-- 8 窗口结束后，客户端跟到新位置 -> 采纳
NOW = 0.45
HANDLER(p, 4, 50.1, 0, 50)
eq(p.x, 50.1, "after window, fresh report accepted")

-- 9 击退：服务端自己在动，状态机不在 moving
p = mk(10, 10, { moving = false })
NOW = 0
HANDLER(p, 1, 10, 0, 10)
p.x = 10.3
NOW = 0.033
HANDLER(p, 2, 10, 0, 10)
eq(p.x, 10.3, "knockback: client report rejected")

-- 10 载具：CanPredictMovement 为假
p = mk(0, 0, { can_predict = false })
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.033
HANDLER(p, 2, 0.2, 0, 0)
eq(p.x, 0, "vehicle: not adopted")

-- 11 nopredict 标签
p = mk(0, 0, { tags = { nopredict = true } })
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.033
HANDLER(p, 2, 0.2, 0, 0)
eq(p.x, 0, "nopredict tag: not adopted")

-- 12 NaN
p = mk(5, 5)
NOW = 0
HANDLER(p, 1, 5, 0, 5)
NOW = 0.033
HANDLER(p, 2, 0 / 0, 0, 5)
eq(p.x, 5, "NaN rejected")

-- 13 长间隔被 MAX_DT 封顶：1.3 格拒绝，1.0 格放行
p = mk(0, 0)
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 5.0
HANDLER(p, 2, 1.3, 0, 0)
eq(p.x, 0, "long gap: 1.3 rejected (capped)")
NOW = 5.033
HANDLER(p, 3, 1.0, 0, 0)
eq(p.x, 1.0, "long gap: 1.0 accepted")

-- 14 加速度 buff：走路速度 9 时，同样的 0.5 格在 33ms 内合法
p = mk(0, 0, { speed = 9 })
NOW = 0
HANDLER(p, 1, 0, 0, 0)
NOW = 0.033
HANDLER(p, 2, 0.5, 0, 0)
eq(p.x, 0.5, "speed buff 9: 0.5@33ms accepted")

-- 15 nil 玩家不崩
eq(pcall(HANDLER, nil, 1, 0, 0, 0) and 1 or 0, 1, "nil player no crash")

print(fails == 0 and "ALL PASSED" or ("FAILED: " .. fails))
if fails > 0 then error("tests failed") end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, to_luastring(harness));
if (status !== lua.LUA_OK) {
  console.error('LUA ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
