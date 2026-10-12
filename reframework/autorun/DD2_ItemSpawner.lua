-- ============================================================
-- DD2_ItemSpawner.lua  —  龙之信条2 刷物品 + 全物品清单导出
-- 依赖: REFramework (DD2 / Dark Arisen 版本，建议最新 nightly)
-- 安装: 放到  <游戏目录>\reframework\autorun\
-- 使用: 游戏内按 Insert 打开 REFramework 菜单 → Script Generated UI → "DD2 刷物品"
-- 导出: <游戏目录>\reframework\data\DD2_ItemList.csv / .json（名称为当前游戏语言）
-- ============================================================

local MOD = "DD2 刷物品"
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

-- ---------- UI ----------
re.on_draw_ui(function()
    if not imgui.tree_node(MOD) then return end
    local changed

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

log_("loaded. getItem3=" .. tostring(getItem3 ~= nil) .. " getItem4=" .. tostring(getItem4 ~= nil)
    .. " msgGet=" .. tostring(msgGet ~= nil))
