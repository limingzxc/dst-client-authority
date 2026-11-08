-- modmain.lua
-- 客户端计算 + 服务端校验。校验规则对齐 Minecraft 的 ServerGamePacketListenerImpl.handleMovePlayer：
--
--   1. 传送 / 击退 / 上下载具期间进入静默窗口，丢弃客户端上报
--      （对应 MC 的 awaitingPositionFromClient：强制位移后旧包一律作废）
--   2. 阈值按「移动速度 × 实际包间隔 × 宽容倍数」计算，不是固定每包距离
--      （对应 MC 的 expectedMoveDist = speed × elapsedTicks）
--   3. 序列号单调递增，过期包直接丢弃
--   4. 连续被拒累计，超阈值打日志（MC 是超阈值踢人，朋友服只记录）

local ENABLED = GetModConfigData("enabled") ~= false
local FORCE_PREDICT = GetModConfigData("force_predict") ~= false
local NO_PAUSE = GetModConfigData("no_pause") ~= false
local SLACK = tonumber(GetModConfigData("slack")) or 2.0
local LOG = GetModConfigData("log") == true

if not ENABLED then return end

local SEND_INTERVAL = 1 / 30
local HEARTBEAT = 1.0

local MIN_DT = 0.016       -- 间隔下限，防止同一帧连发两个包把额度刷小
local MAX_DT = 0.10        -- 间隔上限，防止长时间不发包攒出一次瞬移额度
local MAX_ABS_STEP = 1.5   -- 单包绝对上限
local FORCED_WINDOW = 0.35 -- 强制位移后的静默期
local FALLBACK_SPEED = 6   -- 取不到 locomotor 速度时的兜底（原版跑步速度）

-- ---------------------------------------------------------------------------
-- 服务端：校验并采纳
-- ---------------------------------------------------------------------------

local accepted, rejected = 0, 0

local function walk_speed(player)
    local lom = player.components.locomotor
    if lom ~= nil then
        if type(lom.GetWalkSpeed) == "function" then
            local ok, v = pcall(lom.GetWalkSpeed, lom)
            if ok and type(v) == "number" and v > 0 then return v end
        end
        if type(lom.walkspeed) == "number" and lom.walkspeed > 0 then
            return lom.walkspeed
        end
    end
    return FALLBACK_SPEED
end

local function can_predict(player)
    if player.entity == nil then return true end
    local ok, v = pcall(function() return player.entity:CanPredictMovement() end)
    if ok then return v ~= false end
    return true
end

local function get_state(player, now)
    local st = player._ca
    if st == nil then
        st = {
            seq = -1,
            sx = nil, sz = nil,
            last_ok = nil,
            forced_until = nil,
            streak = 0,
        }
        player._ca = st
    end
    return st
end

local function OnClientPos(player, seq, x, y, z)
    if not TheNet:GetIsServer() then return end
    if player == nil or not player:IsValid() then return end
    if type(seq) ~= "number" or type(x) ~= "number" or type(z) ~= "number" then return end
    if x ~= x or z ~= z then return end
    if math.abs(x) > 1e6 or math.abs(z) > 1e6 then return end

    local now = GetTime()
    local st = get_state(player, now)
    local sx, sy, sz = player.Transform:GetWorldPosition()

    -- 服务端自己刚被强制移动（传送、击退、跳船、上平台）：
    -- 位置突变且状态机不在 moving，开一个静默窗口。对应 MC 的 awaitingPositionFromClient。
    if st.sx ~= nil and distsq(st.sx, st.sz, sx, sz) > 0.0001 then
        if player.sg ~= nil and not player.sg:HasStateTag("moving") then
            st.forced_until = now + FORCED_WINDOW
        end
    end
    st.sx, st.sz = sx, sz

    -- 序列号：过期或重复的包直接丢弃
    if seq <= st.seq then return end
    st.seq = seq

    -- 静默窗口内不受理
    if st.forced_until ~= nil and now < st.forced_until then
        rejected = rejected + 1
        return
    end

    -- 实体级限制：船、平台、被控
    if not can_predict(player) then return end
    if player:HasTag("nopredict") then return end

    -- 阈值：速度 × 实际间隔 × 宽容倍数，并封顶
    local base = st.last_ok or (now - SEND_INTERVAL)
    local dt = math.min(math.max(now - base, MIN_DT), MAX_DT)
    local maxd = math.min(walk_speed(player) * dt * SLACK, MAX_ABS_STEP)

    local cy = (type(y) == "number") and y or sy
    local dx, dy, dz = sx - x, sy - cy, sz - z
    local d2 = dx * dx + dy * dy + dz * dz

    if d2 > maxd * maxd then
        rejected = rejected + 1
        st.streak = st.streak + 1
        if LOG and (st.streak == 1 or st.streak % 10 == 0) then
            print(string.format("[CA] reject streak=%d delta=%.2f max=%.2f",
                st.streak, math.sqrt(d2), maxd))
        end
        return
    end

    if d2 > 0.0001 then
        -- 只采纳 x/z，y 用服务端的，避免把玩家拽到另一层
        player.Transform:SetPosition(x, sy, z)
        accepted = accepted + 1
    end

    st.last_ok = now
    st.streak = 0
end

AddModRPCHandler("PH_CA", "POS", OnClientPos)

local RPC_POS = GetModRPC("PH_CA", "POS")

-- ---------------------------------------------------------------------------
-- 服务端：堵死「暂停预测」这条通道
-- SGwilson.lua 里有 45 处调用 inst.components.playercontroller:RemotePausePrediction(...)，
-- 全部收口在 PlayerController:RemotePausePrediction（components/playercontroller.lua）。
-- 直接覆盖这个组件方法，比去动 player_classified 的 netvar 干净。
-- 注意：player_classified 是 prefab 不是 component，用 AddComponentPostInit 挂不上。
-- ---------------------------------------------------------------------------

if NO_PAUSE then
    AddComponentPostInit("playercontroller", function(self)
        if not self.ismastersim then return end
        if self.RemotePausePrediction == nil then return end
        self.RemotePausePrediction = function() end
    end)
end

-- ---------------------------------------------------------------------------
-- 客户端：拆掉 CanLocomote 的闸门
-- 只保留实体级限制（船、平台、被控），因为那类限制去掉会直接穿模。
-- ---------------------------------------------------------------------------

if FORCE_PREDICT then
    AddComponentPostInit("playercontroller", function(self)
        if self.ismastersim then return end
        if self.CanLocomote == nil then return end

        self.CanLocomote = function(_self)
            if _self.locomotor == nil then return false end
            if _self.inst.entity ~= nil and not _self.inst.entity:CanPredictMovement() then
                return false
            end
            return true
        end
    end)
end

-- ---------------------------------------------------------------------------
-- 客户端：上报坐标
-- 只在位置变化时发，外加 1 秒心跳。序列号单调递增。
-- ---------------------------------------------------------------------------

AddPlayerPostInit(function(player)
    if TheNet:GetIsServer() then return end
    if player ~= ThePlayer then return end

    local seq = 0
    local last_x, last_y, last_z, last_t = nil, nil, nil, 0

    player:DoPeriodicTask(SEND_INTERVAL, function(inst)
        if not inst:IsValid() then return end
        local x, y, z = inst.Transform:GetWorldPosition()
        local now = GetTime()
        if x ~= last_x or y ~= last_y or z ~= last_z or now - last_t >= HEARTBEAT then
            seq = seq + 1
            SendModRPCToServer(RPC_POS, seq, x, y, z)
            last_x, last_y, last_z, last_t = x, y, z, now
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- 服务端：每 10 秒打一次窗口统计，用来判断采纳率。
-- ---------------------------------------------------------------------------

if LOG then
    AddGamePostInit(function()
        if TheWorld == nil then return end
        local last_a, last_r = 0, 0
        TheWorld:DoPeriodicTask(10, function()
            local da = accepted - last_a
            local dr = rejected - last_r
            last_a, last_r = accepted, rejected
            local total = da + dr
            if total > 0 then
                print(string.format("[CA] 10s: accepted=%d rejected=%d (%.1f%% rejected)",
                    da, dr, dr * 100 / total))
            end
        end)
    end)
end
