-- ============================================================
-- DD2_ItemSpawner.lua  v1.1.0  —  龙之信条2 全物品清单导出 / 刷物品 / 穿墙飞天
-- https://github.com/Jindom/DD2-Item-Spawner
-- 依赖: REFramework (DD2 / Dark Arisen 版本，建议最新 nightly)
-- 安装: 放到  <游戏目录>\reframework\autorun\
-- 使用: 游戏内按 Insert 打开 REFramework 菜单 → Script Generated UI → "DD2 刷物品"
-- 导出: <游戏目录>\reframework\data\DD2_ItemList.csv / .json（名称为当前游戏语言）
-- 穿墙飞天: F6 开关；WASD 沿镜头方向移动，Space 上升，Ctrl 下降，Shift 加速（自带防摔伤）
-- ============================================================

local MOD = "DD2 刷物品"
local VERSION = "1.1.0"
local OUT_CSV  = "DD2_ItemList.csv"
local OUT_JSON = "DD2_ItemList.json"

local cfg = {
    idText   = "",
    num      = 1,
    filter   = "",
    scanMax  = 70000,  -- 扫描的最大物品ID
    perFrame = 3000,   -- 每帧扫描数量，防卡顿
}

-- ---------- 类型 / 方法 ----------
local itemMgrT     = sdk.find_type_definition("app.ItemManager")
local getItemDataM = itemMgrT and itemMgrT:get_method("getItemData(System.Int32)")
local getItem3     = itemMgrT and itemMgrT:get_method("getItem(System.Int32, System.Int32, app.Character)")
local getItem4     = itemMgrT and itemMgrT:get_method("getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)")
local optionT      = sdk.find_type_definition("app.ItemDefine.GetItemOption")

local msgT   = sdk.find_type_definition("via.gui.message")
local msgGet = msgT and msgT:get_method("get(System.Guid)")

-- 备用取名方法（仅使用静态方法，避免 null this 崩溃）
local nameFallbacks = {}
do
    local gb = sdk.find_type_definition("app.GUIBase")
    if gb then
        for _, sig in ipairs({ "getElfItemName(System.Int32, System.Boolean)", "getItemName(System.Int32)" }) do
            local m = gb:get_method(sig)
            if m and m:is_static() then table.insert(nameFallbacks, { m = m, two = sig:find("Boolean") ~= nil }) end
        end
    end
end

-- ---------- 状态 ----------
local items    = {}     -- { {id=, name=, type=} }
local status   = ""
local scanning = false
local scanId   = 0
local scanFound = {}
local queue    = {}     -- 待发放 { id=, num= }

do
    local ok, saved = pcall(json.load_file, OUT_JSON)
    if ok and type(saved) == "table" then items = saved end
end

-- ---------- 工具函数 ----------
local function log_(s) log.info("[" .. MOD .. "] " .. s) end

local function getMgr() return sdk.get_managed_singleton("app.ItemManager") end

local function getPlayer()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local ok, p = pcall(cm.call, cm, "get_ManualPlayer()")
    return ok and p or nil
end

local function getItemData(mgr, id)
    if not getItemDataM then return nil end
    local ok, d = pcall(getItemDataM.call, getItemDataM, mgr, id)
    if ok then return d end
    return nil
end

local nameFieldCache = {}
local function findNameGuidField(td)
    local full = td:get_full_name()
    if nameFieldCache[full] ~= nil then return nameFieldCache[full] end
    local found, t = false, td
    while t and not found do
        for _, f in ipairs(t:get_fields()) do
            local ft = f:get_type()
            if not f:is_static() and ft and ft:get_full_name() == "System.Guid" then
                local n = f:get_name():lower()
                if n:find("name") and not n:find("expl") and not n:find("desc") and not n:find("detail") then
                    found = f:get_name(); break
                end
            end
        end
        t = t:get_parent_type()
    end
    nameFieldCache[full] = found
    return found
end

local function resolveName(id, data)
    -- 1) 物品数据里的名称 GUID → 本地化文本
    if msgGet and data then
        local ok, field = pcall(findNameGuidField, data:get_type_definition())
        if ok and field then
            local ok2, s = pcall(function() return msgGet:call(nil, data:get_field(field)) end)
            if ok2 and s and tostring(s) ~= "" then return tostring(s) end
        end
    end
    -- 2) 备用 GUI 取名
    for _, fb in ipairs(nameFallbacks) do
        local ok, s
        if fb.two then ok, s = pcall(fb.m.call, fb.m, nil, id, false)
        else ok, s = pcall(fb.m.call, fb.m, nil, id) end
        if ok and s and tostring(s) ~= "" then return tostring(s) end
    end
    return ""
end

local function csvEscape(s)
    local r = tostring(s or ""):gsub('"', '""')
    return '"' .. r .. '"'
end

local function writeOut()
    table.sort(items, function(a, b) return a.id < b.id end)
    local ok, err = pcall(function()
        local f = assert(io.open(OUT_CSV, "w"))
        f:write("\239\187\191id,name,type\n") -- UTF-8 BOM，Excel 直接打开不乱码
        for _, it in ipairs(items) do
            f:write(string.format("%d,%s,%s\n", it.id, csvEscape(it.name), it.type))
        end
        f:close()
    end)
    if not ok then log_("CSV 写入失败: " .. tostring(err)) end
    json.dump_file(OUT_JSON, items)
end

local function giveItem(id, num)
    local mgr, pl = getMgr(), getPlayer()
    if not mgr or not pl then return "失败：未进入游戏或找不到玩家" end
    if not getItemData(mgr, id) then return "失败：无效物品ID " .. id end

    if getItem3 then
        local ok, err = pcall(getItem3.call, getItem3, mgr, id, num, pl)
        if ok then return string.format("已添加 %d x%d", id, num) end
        log_("getItem(3) 失败: " .. tostring(err))
    end
    if getItem4 and optionT then
        local ok, err = pcall(function()
            local opt = ValueType.new(optionT)
            getItem4:call(mgr, id, num, pl, opt)
        end)
        if ok then return string.format("已添加 %d x%d", id, num) end
        return "失败: " .. tostring(err)
    end
    return "失败：找不到 getItem 方法（游戏/REFramework 版本不匹配）"
end

local function matches(it, f)
    if f == "" then return true end
    if tostring(it.id) == f then return true end
    return (it.name or ""):lower():find(f:lower(), 1, true) ~= nil
end

-- ---------- 游戏线程：扫描 + 发放 ----------
re.on_application_entry("UpdateBehavior", function()
    if scanning then
        local mgr = getMgr()
        if not mgr then status = "等待 ItemManager..."; return end
        local stop = math.min(scanId + cfg.perFrame, cfg.scanMax)
        for id = scanId, stop do
            local d = getItemData(mgr, id)
            if d then
                local tn = d:get_type_definition():get_name()
                table.insert(scanFound, { id = id, name = resolveName(id, d), type = tn })
            end
        end
        scanId = stop + 1
        status = string.format("扫描中 %d / %d，已找到 %d", scanId, cfg.scanMax, #scanFound)
        if scanId > cfg.scanMax then
            scanning = false
            items = scanFound
            writeOut()
            status = string.format("完成：%d 个物品 → reframework\\data\\%s", #items, OUT_CSV)
            log_(status)
        end
    end

    local n = 0
    while #queue > 0 and n < 10 do
        local job = table.remove(queue, 1)
        status = giveItem(job.id, job.num)
        n = n + 1
    end
end)

-- ============================================================
-- 穿墙飞天（noclip fly）v2
-- DD2 的角色有位置历史（PosRotContext），直接改 Transform 只会移动镜头、
-- 模型会被拉回原处。所以这里：
--   1) 关闭角色的 CharacterController（碰撞 + 重力）
--   2) 在游戏读取玩家输入时（app.UserInputManager.updateInput 之后），
--      用游戏自带的 app.Character.warp(位置, 旋转, ResetPosRotContext) 移动角色
--   3) 同时清空游戏的移动/按键输入，避免角色跟着走路、跳跃、攻击
--   4) 每帧重置 FallInfo（摔落高度），关闭后继续保护数秒，防摔伤
-- ============================================================
local VK = {
    TOGGLE = { 0x75 },             -- F6
    W = { 0x57 }, A = { 0x41 }, S = { 0x53 }, D = { 0x44 },
    UP   = { 0x20 },               -- Space
    DOWN = { 0x11, 0xA2, 0xA3 },   -- Ctrl / LCtrl / RCtrl
    FAST = { 0x10, 0xA0, 0xA1 },   -- Shift / LShift / RShift
}
local BTN_FIELDS = { "ButtonOnFlags", "ButtonTriggerFlags", "ButtonReleaseFlags", "ButtonRepeatFlags" }
local WARP_SIG = "warp(via.vec3, via.Quaternion, app.CharacterWarpOption)"
local CC_TYPE = "via.physics.CharacterController"
local REBASE_JUMP = 30.0   -- 单帧被外部移动超过此距离：视为游戏传送，跟随

local fly = {
    enabled   = false,
    request   = nil,    -- UI / 热键只写请求，游戏线程执行
    speed     = 12.0,   -- 米/秒
    fastMult  = 4.0,
    safeLand  = true,   -- 关闭后防摔伤
    safeLandSec = 10.0,
    status    = "关闭",
    player = nil, xform = nil, cc = nil, ccWasEnabled = nil,
    target = nil, lastWritten = nil, lastActual = nil, lastClock = nil,
    togglePrev = false, fallUntil = nil, revertWarned = false,
    useWarp = true, hookOk = false, lastTickClock = nil,
}

local function keyDown(list)
    for _, k in ipairs(list) do
        local ok, d = pcall(function() return reframework:is_key_down(k) end)
        if ok and d then return true end
    end
    return false
end

local function addrOf(obj)
    if obj == nil then return nil end
    local ok, a = pcall(function() return obj:get_address() end)
    if ok then return a end
    return tostring(obj)
end

local function field(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

local function xformOf(pl)
    local tr = field(pl, "<Transform>k__BackingField")
    if tr then return tr end
    local ok, t = pcall(function() return pl:get_GameObject():get_Transform() end)
    return ok and t or nil
end

local function getCC(pl)
    local cc = field(pl, "<CharaController>k__BackingField")
    if cc then return cc end
    local ok, c = pcall(function()
        return pl:get_GameObject():call("getComponent(System.Type)", sdk.typeof(CC_TYPE))
    end)
    return ok and c or nil
end

local warpOptCache
local function warpOpt()
    if warpOptCache == nil then
        local ok, v = pcall(function()
            return sdk.find_type_definition("app.CharacterWarpOption"):get_field("ResetPosRotContext"):get_data(nil)
        end)
        warpOptCache = ok and v or false
    end
    return warpOptCache or nil
end

-- 用游戏自己的 warp 移动角色（同时重置位置历史）；不可用时退回 set_Position
local function placeAt(pl, xf, pos)
    if fly.useWarp then
        local opt = warpOpt()
        local ok = opt ~= nil and pcall(function()
            pl:call(WARP_SIG, pos, xf:get_Rotation(), opt)
        end)
        if ok then return true end
        fly.useWarp = false
        log_("Character.warp 不可用，改用 set_Position（模型可能不跟随）")
    end
    pcall(xf.set_Position, xf, pos)
    if fly.cc then pcall(fly.cc.call, fly.cc, "warp") end
    return false
end

local function resetFall(pl, xf)
    pcall(function()
        local up = xf:get_UniversalPosition()
        local fi = pl["<FallInfo>k__BackingField"]
        fi:call("resetBaseHeight(via.Position)", up)
        fi:call("set_HighestPositionOnAir(via.Position)", up)
        fi:call("resetFallHeight()")
    end)
end

local function flyOn()
    local pl = getPlayer()
    if not pl then fly.status = "开启失败：未进入游戏"; return end
    local xf = xformOf(pl)
    if not xf then fly.status = "开启失败：找不到玩家 Transform"; return end
    local ok, pos = pcall(xf.get_Position, xf)
    if not ok or not pos then fly.status = "开启失败：读取位置出错"; return end
    fly.player, fly.xform = pl, xf
    fly.target, fly.lastWritten, fly.lastActual = pos, pos, pos
    fly.cc = getCC(pl)
    if fly.cc then
        local ok2, en = pcall(fly.cc.call, fly.cc, "get_Enabled")
        fly.ccWasEnabled = (not ok2) or en
        pcall(fly.cc.call, fly.cc, "set_Enabled", false)
    end
    fly.useWarp, fly.revertWarned = true, false
    fly.lastClock = os.clock()
    fly.fallUntil = nil
    fly.enabled = true
    fly.status = fly.cc and "开启" or "开启（未找到碰撞组件，可能无法穿墙）"
    log_("fly on, cc=" .. tostring(fly.cc ~= nil) .. " warpOpt=" .. tostring(warpOpt() ~= nil)
        .. " inputHook=" .. tostring(fly.hookOk))
end

local function flyOff(reason)
    local pl, xf = fly.player, fly.xform
    if pl and xf and fly.target then pcall(placeAt, pl, xf, fly.target) end  -- 原地落定，同步历史
    if fly.cc then
        pcall(fly.cc.call, fly.cc, "set_Enabled", fly.ccWasEnabled ~= false)
        pcall(fly.cc.call, fly.cc, "warp")
    end
    if fly.safeLand and pl then
        fly.fallUntil = { player = pl, xform = xf, t = os.clock() + fly.safeLandSec }
    end
    fly.enabled = false
    fly.player, fly.xform, fly.cc, fly.ccWasEnabled = nil, nil, nil, nil
    fly.target, fly.lastWritten, fly.lastActual = nil, nil, nil
    fly.status = reason or "关闭"
    log_("fly off: " .. fly.status)
end

local function flyMoveDir()
    local f = (keyDown(VK.W) and 1 or 0) - (keyDown(VK.S) and 1 or 0)
    local r = (keyDown(VK.D) and 1 or 0) - (keyDown(VK.A) and 1 or 0)
    local u = (keyDown(VK.UP) and 1 or 0) - (keyDown(VK.DOWN) and 1 or 0)
    if f == 0 and r == 0 and u == 0 then return nil end
    local ok, m = pcall(function()
        return sdk.get_primary_camera():get_GameObject():get_Transform():get_WorldMatrix()
    end)
    if not ok or not m then return nil end
    local fwd   = m[2]:to_vec3() * -1.0   -- RE 引擎相机朝 -Z
    local right = m[0]:to_vec3()
    local dir = fwd * f + right * r + Vector3f.new(0, u, 0)
    if dir:length() < 1e-4 then return nil end
    return dir:normalized()
end

local function uiIsOpen()
    local ok, v = pcall(function() return reframework:is_drawing_ui() end)
    return ok and v or false
end

-- 每帧移动：优先在玩家输入处理完之后执行（inp = 玩家的输入对象，可为 nil）
local function flyTick(inp)
    if not fly.enabled then return end
    local pl = fly.player
    local xf = fly.xform

    local now = os.clock()
    local dt = math.max(0, math.min(now - (fly.lastClock or now), 0.1))
    fly.lastClock = now
    fly.lastTickClock = now

    local ok, actual = pcall(xf.get_Position, xf)
    if not ok or not actual then error("Transform 失效") end
    local drift = (actual - fly.lastWritten):length()
    if drift > REBASE_JUMP then
        if (actual - fly.lastActual):length() > REBASE_JUMP then
            fly.target = fly.target + (actual - fly.lastWritten)   -- 游戏传送 / 原点偏移，跟随
        elseif not fly.revertWarned then
            fly.revertWarned = true
            fly.status = "警告：位置被游戏拉回（模型可能不跟随），见日志"
            log_("position reverted by game: actual=" .. tostring(actual.x) .. "," .. tostring(actual.y) .. ","
                .. tostring(actual.z) .. " useWarp=" .. tostring(fly.useWarp))
        end
    end
    fly.lastActual = actual

    -- 游戏状态机可能重新打开碰撞，保持关闭
    if fly.cc then
        local ok2, en = pcall(fly.cc.call, fly.cc, "get_Enabled")
        if ok2 and en then pcall(fly.cc.call, fly.cc, "set_Enabled", false) end
    end

    -- 菜单打开时不飞（避免打字乱飞）
    if not uiIsOpen() then
        local dir = flyMoveDir()
        if dir then
            local spd = fly.speed * (keyDown(VK.FAST) and fly.fastMult or 1.0)
            fly.target = fly.target + dir * (spd * dt)
        end
    end
    -- 飞行期间始终屏蔽游戏自身的移动 / 跳跃 / 攻击输入（镜头输入保留）
    if inp then
        for _, f in ipairs(BTN_FIELDS) do pcall(function() inp:set_field(f, 0) end) end
        pcall(function() inp:call("setAxisL(System.Single, System.Single)", 0.0, 0.0) end)
    end

    placeAt(pl, xf, fly.target)
    fly.lastWritten = fly.target
    resetFall(pl, xf)
end

local function safeTick(inp)
    local ok, err = pcall(flyTick, inp)
    if not ok then
        log_("fly error: " .. tostring(err))
        pcall(flyOff, "已自动关闭（出错，见日志）")
    end
end

-- 挂到游戏输入更新之后（与 DimensionDoor 同一时机，warp 才能生效）
pcall(function()
    local m = sdk.find_type_definition("app.UserInputManager"):get_method("updateInput")
    if not m then return end
    local cur
    sdk.hook(m, function(args)
        cur = fly.enabled and sdk.to_managed_object(args[3]) or nil
    end, function(ret)
        if cur and fly.enabled then
            local inp = cur
            cur = nil
            local okIn, mine = pcall(function() return fly.player:get_Input() end)
            if okIn and mine and addrOf(mine) == addrOf(inp) then safeTick(inp) end
        end
        return ret
    end)
    fly.hookOk = true
end)

-- 游戏线程：开关、玩家变化检测、关闭后防摔伤、输入钩子失效时的兜底
re.on_application_entry("UpdateBehavior", function()
    local t = keyDown(VK.TOGGLE)
    if t and not fly.togglePrev then fly.request = not fly.enabled end
    fly.togglePrev = t
    if fly.request ~= nil then
        local want = fly.request
        fly.request = nil
        if want and not fly.enabled then pcall(flyOn) elseif not want and fly.enabled then pcall(flyOff) end
    end

    if fly.enabled then
        local pl = getPlayer()
        if not pl or addrOf(pl) ~= addrOf(fly.player) then
            pcall(flyOff, "已自动关闭（玩家对象变化）")
        else
            -- 输入钩子 0.2 秒没触发（版本变化 / 钩子失效）→ 在这里兜底执行
            local now = os.clock()
            if not fly.hookOk or not fly.lastTickClock or now - fly.lastTickClock > 0.2 then
                safeTick(nil)
            end
        end
    end

    local fu = fly.fallUntil
    if fu then
        local pl = getPlayer()
        if os.clock() > fu.t or not pl or addrOf(pl) ~= addrOf(fu.player) then
            fly.fallUntil = nil
        else
            resetFall(fu.player, fu.xform)
        end
    end
end)

-- ---------- UI ----------
re.on_draw_ui(function()
    if not imgui.tree_node(MOD) then return end
    local changed

    if imgui.tree_node("穿墙飞天（F6 开关）") then
        local c, v = imgui.checkbox("启用穿墙飞天", fly.enabled)
        if c then fly.request = v end
        changed, fly.speed = imgui.slider_float("速度 (米/秒)", fly.speed, 1.0, 100.0)
        changed, fly.fastMult = imgui.slider_float("Shift 加速倍率", fly.fastMult, 1.0, 10.0)
        changed, fly.safeLand = imgui.checkbox("关闭后 10 秒内防摔伤", fly.safeLand)
        imgui.text("状态：" .. fly.status)
        imgui.text("WASD 沿镜头方向  Space 上升  Ctrl 下降  Shift 加速")
        imgui.text("飞行中游戏自身的移动/跳跃/攻击输入会被屏蔽；菜单打开时不移动")
        imgui.tree_pop()
    end
    imgui.separator()

    imgui.text(string.format("物品库：%d 条   %s", #items, status))
    if imgui.button(scanning and "扫描中..." or "导出全物品清单（CSV/JSON）") and not scanning then
        scanning, scanId, scanFound = true, 0, {}
    end

    imgui.separator()
    changed, cfg.idText = imgui.input_text("物品ID", cfg.idText)
    changed, cfg.num = imgui.drag_int("数量", cfg.num, 1, 1, 999)
    if imgui.button("添加到背包") then
        local id = tonumber(cfg.idText)
        if id then table.insert(queue, { id = id, num = cfg.num }) else status = "请输入数字ID" end
    end

    imgui.separator()
    changed, cfg.filter = imgui.input_text("搜索（名称/ID）", cfg.filter)
    local shown, hits = 0, {}
    for _, it in ipairs(items) do
        if matches(it, cfg.filter) then table.insert(hits, it) end
    end
    imgui.text(string.format("匹配 %d 条（最多显示 60 条，点击选中）", #hits))
    if cfg.filter ~= "" and #hits > 0 and #hits <= 100 then
        if imgui.button(string.format("把这 %d 个全部各加 x%d", #hits, cfg.num)) then
            for _, it in ipairs(hits) do table.insert(queue, { id = it.id, num = cfg.num }) end
        end
    end
    for _, it in ipairs(hits) do
        if shown >= 60 then break end
        if imgui.button(string.format("%d  %s  [%s]##dd2item%d", it.id, it.name ~= "" and it.name or "?", it.type, it.id)) then
            cfg.idText = tostring(it.id)
        end
        shown = shown + 1
    end

    imgui.tree_pop()
end)

log_("loaded v" .. VERSION .. ". getItem3=" .. tostring(getItem3 ~= nil) .. " getItem4=" .. tostring(getItem4 ~= nil)
    .. " msgGet=" .. tostring(msgGet ~= nil))
