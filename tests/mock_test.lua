-- 模拟 REFramework 运行时 + DD2 角色行为的离线测试（不需要游戏）
-- 用法: lua tests/mock_test.lua reframework/autorun/DD2_ItemSpawner.lua
--
-- 模拟的 DD2 行为：
--   * 位置历史：每帧 UpdateBehavior 把 Transform 还原成历史位置；
--     只有 Character.warp(..., ResetPosRotContext) 会改写历史（直接 set_Position 会被拉回）
--   * 模型位置 = UpdateMotion 阶段的 Transform（镜头 = 帧末 Transform）
--   * CharacterController 开启时有重力、下落累计摔落高度，落地 >5m 摔伤
--   * 游戏自身输入：左摇杆走路、按键跳跃
local SCRIPT = arg[1]
local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (extra and ("  -- " .. tostring(extra)) or "")) end
end
local function approx(a, b, eps) return math.abs(a - b) < (eps or 1e-3) end

-- ---------- Vector3f ----------
local V = {}; V.__index = V
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return vec(a.x * b, a.y * b, a.z * b) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:normalized() local l = self:length(); return vec(self.x / l, self.y / l, self.z / l) end
function V:to_vec3() return vec(self.x, self.y, self.z) end
Vector3f = { new = vec }
local function vstr(v) return v and string.format("(%.3f,%.3f,%.3f)", v.x, v.y, v.z) or "nil" end

-- ---------- camera (RE camera looks -Z) ----------
local camYaw = 0
local function camMatrix()
  local c, s = math.cos(camYaw), math.sin(camYaw)
  return { [0] = vec(c, 0, -s), [1] = vec(0, 1, 0), [2] = vec(s, 0, c), [3] = vec(0, 0, 0) }
end

-- ---------- DD2 character model ----------
local WARP_SIG = "warp(via.vec3, via.Quaternion, app.CharacterWarpOption)"
local RESET_OPT = { name = "ResetPosRotContext" }
local GROUND_Y = 0
local function newPlayer(addr, opts)
  opts = opts or {}
  local p = {
    addr = addr, xpos = vec(100, GROUND_Y, 200), hist = vec(100, GROUND_Y, 200), model = nil,
    cc = (not opts.noCC) and { enabled = true, warps = 0 } or nil,
    fall = { height = 0, resets = 0 }, damage = 0, jumps = 0, walked = 0,
    warpCalls = 0, warpBroken = opts.warpBroken, throwOnWarp = false,
  }
  local input = { fields = {}, axisL = { 0, 0 } }
  function input.set_field(self, f, v) self.fields[f] = v end
  function input.get_field(self, f) return self.fields[f] end
  function input.call(self, sig, x, y) if sig == "setAxisL(System.Single, System.Single)" then self.axisL = { x, y } end end
  function input.get_address() return addr + 1 end
  p.input = input

  local xf = {}
  function xf.get_Position() return vec(p.xpos.x, p.xpos.y, p.xpos.z) end
  function xf.set_Position(self, v) p.xpos = vec(v.x, v.y, v.z) end      -- NOT written to history
  function xf.get_Rotation() return "rot" end
  function xf.get_UniversalPosition() return vec(p.xpos.x, p.xpos.y, p.xpos.z) end
  p.xform = xf

  local ccObj = p.cc and {
    call = function(self, sig, ...)
      if sig == "get_Enabled" then return p.cc.enabled end
      if sig == "set_Enabled" then p.cc.enabled = ...; return end
      if sig == "warp" then p.cc.warps = p.cc.warps + 1; return end
    end } or nil
  local fallInfo = { call = function(self, sig) if sig == "resetFallHeight()" then p.fall.height = 0; p.fall.resets = p.fall.resets + 1 end end }
  local go = {
    get_Transform = function() return xf end,
    call = function(self, sig) if sig == "getComponent(System.Type)" then return ccObj end end,
  }
  local obj = {
    ["<Transform>k__BackingField"] = xf,
    ["<CharaController>k__BackingField"] = ccObj,
    ["<FallInfo>k__BackingField"] = fallInfo,
  }
  function obj.get_GameObject() return go end
  function obj.get_address() return addr end
  function obj.get_Input() return input end
  function obj.get_CharaID() return 1 end
  function obj.get_Valid() return true end
  function obj.call(self, sig, pos, rot, opt)
    if sig == WARP_SIG then
      if p.warpBroken then error("no such method") end
      if p.throwOnWarp then error("boom") end
      p.warpCalls = p.warpCalls + 1
      p.xpos = vec(pos.x, pos.y, pos.z)
      if opt == RESET_OPT then p.hist = vec(pos.x, pos.y, pos.z) end
      return
    end
  end
  p.obj = obj
  return p
end
local P = newPlayer(0x1000)
local currentPlayer = P

-- ---------- REFramework API mocks ----------
local keys, uiOpen = {}, false
reframework = { is_key_down = function(self, k) return keys[k] == true end, is_drawing_ui = function() return uiOpen end }
local clockT = 0
os.clock = function() return clockT end

local itemData, given = {}, {}
for _, id in ipairs({ 3, 10, 4999 }) do
  itemData[id] = { get_type_definition = function() return {
      get_name = function() return "ItemCommonParam" end, get_full_name = function() return "app.ItemCommonParam" end,
      get_fields = function() return { { get_type = function() return { get_full_name = function() return "System.Guid" end } end,
        is_static = function() return false end, get_name = function() return "_NameMsgId" end } } end,
      get_parent_type = function() return nil end } end,
    get_field = function(_, f) return "g" .. id end }
end
local hooks = {}
local hookAvailable = true
local mgr = {}

-- ---------- enemies ----------
-- 模拟 Dark Arisen：敌人集合没有 get_Item；死亡行为可配置
local HP_SIG = "setHpValue(System.Single, System.Boolean)"
local KILL_SIG = "killAndSetDieLoop(app.Character.KillAndSetDieLoopOption)"
local enemies = {}
local enemyManagerPresent = true
local listShape = "ToArray"     -- ToArray | _items | _entries | get_elements | get_Item | none
local hp0Kills = true           -- true: HP 归零即死亡；false: 需要 killAndSetDieLoop
local function arrayOf(t)
  return { get_elements = function() local c = {} for i, v in ipairs(t) do c[i] = v end return c end }
end
local function newEnemy(name, hp, dist, opts)
  opts = opts or {}
  local e = { name = name, hp = hp, maxHp = hp, dist = dist, dead = hp <= 0, revived = false, sets = 0, kills = 0,
              boss = opts.boss, broken = opts.broken, noDie = opts.noDie or false, attackNoDie = opts.noDie or false }
  local function tryDie()
    if e.hp <= 0 and not e.noDie and hp0Kills then e.dead = true end
  end
  local hit = {
    call = function(self, sig, v, b)
      if sig ~= HP_SIG then error("bad sig " .. sig) end
      if e.broken then error("hit controller broken") end
      e.sets = e.sets + 1
      if e.dead and v > 0 then e.revived = true end
      e.hp = v
      tryDie()
    end,
    get_IsNoDie = function() return e.noDie end,
    set_IsNoDie = function(self, v) e.noDie = v end,
    get_IsAttackNoDie = function() return e.attackNoDie end,
    set_IsAttackNoDie = function(self, v) e.attackNoDie = v end,
    get_IsDie = function() return e.dead end,
  }
  local chara
  chara = {
    get_Hit = function() return hit end,
    get_Hp = function() return e.hp end,
    get_IsDead = function() return e.dead end,
    get_DistanceSqFromPlayer = function() return e.dist * e.dist end,
    get_type_definition = function() return { get_full_name = function() return "app.Character" end } end,
    call = function(self, sig, ...)
      if sig == KILL_SIG then
        local opt = ...
        assert(opt ~= nil, "option missing")
        if e.broken then error("broken") end
        if e.noDie then return end            -- 剧情保护时游戏函数也杀不死
        e.kills = e.kills + 1; e.hp = 0; e.dead = true
        return
      end
      local g = chara[sig]; if g then return g(chara) end
      if sig == "get_CharaIDString" then return name end
      if sig == "get_OriginalMaxHp" then return e.maxHp end
      error("no method " .. sig)
    end,
  }
  e.obj = { get_Chara = function() return chara end,
            get_type_definition = function() return { get_full_name = function() return "app.EnemyCharacter" end } end }
  e.chara = chara
  return e
end
local function enemyList()
  local objs = {}
  for i, en in ipairs(enemies) do objs[i] = en.obj end
  local col = {
    get_Count = function() return #objs end,
    get_type_definition = function() return { get_full_name = function() return "System.Collections.Generic.List`1<app.EnemyCharacter>(" .. listShape .. ")" end } end,
    get_field = function(self, f)
      if listShape == "_items" and f == "_items" then
        local padded = {} for i, v in ipairs(objs) do padded[i] = v end
        padded[#padded + 1] = objs[1]      -- capacity > count: extra slots must be ignored
        return arrayOf(padded)
      end
      if listShape == "_entries" and f == "_entries" then
        local ent = {}
        for i, v in ipairs(objs) do ent[i] = { get_field = function(_, k) if k == "Value" then return v end end } end
        return arrayOf(ent)
      end
      return nil
    end,
    call = function(self, sig, i)
      if sig == "get_Item" and listShape == "get_Item" then return objs[i + 1] end
      error("method not found: " .. sig)
    end,
  }
  if listShape == "ToArray" then col.ToArray = function() return arrayOf(objs) end end
  if listShape == "get_elements" then col.get_elements = function() local c = {} for i, v in ipairs(objs) do c[i] = v end return c end end
  return col
end
-- player attack: any positive damage
local function hitEnemy(e, dmg) if e.dead then return end e.hp = math.max(0, e.hp - dmg); if e.hp <= 0 and not e.noDie then e.dead = true end end
local typeMethods = {
  ["app.HitController"] = { "setHpValue|System.Single,System.Boolean", "get_Hp|", "get_IsNoDie|", "set_IsNoDie|System.Boolean", "get_IsDie|", "update|" },
  ["app.Character"] = { "get_Hp|", "get_IsDead|", "warp|via.vec3,via.Quaternion,app.CharacterWarpOption", "killAndSetDieLoop|app.Character.KillAndSetDieLoopOption" },
  ["app.EnemyManager"] = { "getAllEnemies|", "get_EnemyCount|" },
}
local function typeDef(n)
  return {
    get_full_name = function() return n end,
    get_parent_type = function() return nil end,
    get_methods = function()
      local out = {}
      for _, spec in ipairs(typeMethods[n] or {}) do
        local name, ps = spec:match("^(.-)|(.*)$")
        local params = {}
        for p in ps:gmatch("[^,]+") do table.insert(params, { get_full_name = function() return p end }) end
        table.insert(out, { get_name = function() return name end, get_param_types = function() return params end })
      end
      return out
    end,
  }
end
local killOptType = {
  get_parent_type = function() return { get_full_name = function() return "System.Enum" end } end,
  is_value_type = function() return true end,
  get_fields = function() return {
    { get_name = function() return "None" end, is_static = function() return true end, get_data = function() return 0 end },
    { get_name = function() return "NoDrop" end, is_static = function() return true end, get_data = function() return 1 end } } end,
}
sdk = {
  find_type_definition = function(n)
    if typeMethods[n] then return typeDef(n) end
    if n == "app.Character.KillAndSetDieLoopOption" then return killOptType end
    if n == "app.CharacterWarpOption" then
      return { get_field = function(_, f) return { get_data = function() return f == "ResetPosRotContext" and RESET_OPT or nil end } end }
    end
    return {
      get_method = function(_, sig)
        if n == "app.UserInputManager" then return hookAvailable and { name = sig } or nil end
        return { is_static = function() return true end, call = function(self, this, ...)
          if sig == "getItemData(System.Int32)" then return itemData[...] end
          if sig:find("^getItem%(") then table.insert(given, { ... }) return true end
          if sig == "get(System.Guid)" then return "名-" .. tostring(...) end end }
      end }
  end,
  get_managed_singleton = function(n)
    if n == "app.CharacterManager" then return { call = function() return currentPlayer and currentPlayer.obj end } end
    if n == "app.EnemyManager" then
      return enemyManagerPresent and { getAllEnemies = function() return enemyList() end } or nil
    end
    return mgr
  end,
  get_primary_camera = function() return { get_GameObject = function() return { get_Transform = function() return { get_WorldMatrix = function() return camMatrix() end } end } end } end,
  typeof = function(n) return n end,
  hook = function(m, pre, post) table.insert(hooks, { m = m, pre = pre, post = post }) end,
  to_managed_object = function(x) return x end,
}
ValueType = { new = function() return {} end }
local logLines = {}
log = { info = function(s) table.insert(logLines, s); io.write("      log: ", s, "\n") end }
json = { load_file = function() return nil end, dump_file = function() end }

local cb = { post = {}, pre = {} }
local function addcb(t, n, f) t[n] = t[n] or {}; table.insert(t[n], f) end
re = {
  on_application_entry = function(n, f) addcb(cb.post, n, f) end,
  on_pre_application_entry = function(n, f) addcb(cb.pre, n, f) end,
  on_draw_ui = function(f) cb.ui = f end,
}
local ui = { clicks = {}, checkbox = {}, texts = {} }
imgui = {
  tree_node = function() return true end, tree_pop = function() end, separator = function() end,
  text = function(s) table.insert(ui.texts, s) end,
  button = function(l) return ui.clicks[l] end,
  input_text = function(_, v) return false, v end,
  drag_int = function(_, v) return false, v end,
  slider_float = function(_, v) return false, v end,
  checkbox = function(l, v) local o = ui.checkbox[l]; if o ~= nil then ui.checkbox[l] = nil; return true, o end return false, v end,
}

local function loadScript()
  hooks, cb = {}, { post = {}, pre = {} }
  dofile(SCRIPT)
end
loadScript()

-- ---------- one game frame ----------
local function run(t, n) for _, f in ipairs(t[n] or {}) do f() end end
local function frame(dt)
  clockT = clockT + (dt or 0.1)
  local p = currentPlayer
  -- 1) input phase: device -> player's input object, then hook
  if p then
    p.input.fields = {}
    p.input.axisL = { 0, 0 }
    if keys[0x57] then p.input.axisL = { 0, 1 } end            -- game walks forward on W
    if keys[0x20] then p.input.fields.ButtonTriggerFlags = 1 end -- game jumps on Space
    for _, h in ipairs(hooks) do h.pre({ nil, nil, p.input }) end
    for _, h in ipairs(hooks) do h.post(nil) end
  end
  -- 2) game behavior: position history + own movement + gravity
  run(cb.pre, "UpdateBehavior")
  if p then
    p.xpos = vec(p.hist.x, p.hist.y, p.hist.z)                  -- direct transform writes are reverted
    if p.input.axisL[2] ~= 0 then p.hist = p.hist + vec(0, 0, -0.5); p.walked = p.walked + 1 end
    if (p.input.fields.ButtonTriggerFlags or 0) ~= 0 then p.jumps = p.jumps + 1 end
    if p.cc and p.cc.enabled then
      if p.hist.y > GROUND_Y then
        local d = math.min(2.0, p.hist.y - GROUND_Y)
        p.hist = p.hist + vec(0, -d, 0); p.fall.height = p.fall.height + d
        if p.hist.y <= GROUND_Y then
          if p.fall.height > 5 then p.damage = p.damage + p.fall.height end
          p.fall.height = 0
        end
      end
    end
    p.xpos = vec(p.hist.x, p.hist.y, p.hist.z)
  end
  run(cb.post, "UpdateBehavior")
  -- 3) motion: model is posed from the transform here
  if p then p.model = p.xform.get_Position() end
  run(cb.post, "LateUpdateBehavior")
  run(cb.pre, "BeginRendering")
end
local function drawUI() ui.texts = {}; cb.ui() end
local function statusText() for _, t in ipairs(ui.texts) do if t:find("^状态") then return t end end return "" end
local function fly(on) ui.checkbox["启用穿墙飞天"] = on; drawUI(); frame(); drawUI() end
local function moveFrame(keyList, dt) for _, k in ipairs(keyList) do keys[k] = true end frame(dt or 0.1) for _, k in ipairs(keyList) do keys[k] = nil end end

-- ===================== Tests =====================
check("input hook installed", #hooks == 1)
check("callbacks registered", cb.post.UpdateBehavior and #cb.post.UpdateBehavior == 3 and cb.ui)

-- --- 1. toggle via F6 (edge only)
frame()
keys[0x75] = true; frame(); frame(); keys[0x75] = nil; frame(); drawUI()
check("F6 enables fly", statusText() == "状态：开启", statusText())
check("CharacterController disabled", P.cc.enabled == false)
frame(); drawUI()
check("holding/releasing F6 does not re-toggle", statusText() == "状态：开启")

-- --- 2. THE BUG: model must follow, not just the camera
local s = P.model
for i = 1, 10 do moveFrame({ 0x20 }) end                     -- rise 10 x 1.2m
check("model rises with fly (bug fix)", approx(P.model.y, s.y + 12), "model " .. vstr(P.model) .. " start " .. vstr(s))
check("transform == model (camera and model agree)", approx((P.xform.get_Position() - P.model):length(), 0), vstr(P.xform.get_Position()) .. " vs " .. vstr(P.model))
check("history updated by warp (no snap-back)", approx(P.hist.y, P.model.y))
check("uses Character.warp", P.warpCalls > 0)

-- --- 3. hover: no gravity, no input → stays
s = P.model
for i = 1, 5 do frame() end
check("hovers in place (no gravity)", approx((P.model - s):length(), 0), vstr(P.model - s))

-- --- 4. directions & speed (12 m/s, dt 0.1 → 1.2 m)
s = P.model; moveFrame({ 0x57 })
check("W moves 1.2m along camera -Z", approx(P.model.z, s.z - 1.2) and approx(P.model.x, s.x), vstr(P.model - s))
s = P.model; moveFrame({ 0x53 })
check("S moves along +Z", approx(P.model.z, s.z + 1.2), vstr(P.model - s))
s = P.model; moveFrame({ 0x44 })
check("D moves along +X", approx(P.model.x, s.x + 1.2), vstr(P.model - s))
s = P.model; moveFrame({ 0x41 })
check("A moves along -X", approx(P.model.x, s.x - 1.2), vstr(P.model - s))
s = P.model; moveFrame({ 0xA2 })
check("LCtrl descends", approx(P.model.y, s.y - 1.2), vstr(P.model - s))
s = P.model; moveFrame({ 0x11 })
check("generic Ctrl descends", approx(P.model.y, s.y - 1.2), vstr(P.model - s))
s = P.model; moveFrame({ 0x57, 0x10 })
check("Shift x4", approx(P.model.z, s.z - 4.8), vstr(P.model - s))
s = P.model; moveFrame({ 0x57, 0x44 })
check("diagonal normalized", approx((P.model - s):length(), 1.2), vstr(P.model - s))
camYaw = math.pi / 2; s = P.model; moveFrame({ 0x57 }); camYaw = 0
check("W follows camera yaw", approx(P.model.x, s.x - 1.2) and approx(P.model.z, s.z), vstr(P.model - s))
s = P.model; moveFrame({ 0x57 }, 5.0)
check("dt clamped to 0.1s", approx((P.model - s):length(), 1.2), vstr(P.model - s))

-- --- 5. game input suppressed while flying
local walked, jumps = P.walked, P.jumps
for i = 1, 3 do moveFrame({ 0x57, 0x20 }) end
check("game walk input suppressed", P.walked == walked, P.walked - walked)
check("game jump input suppressed", P.jumps == jumps, P.jumps - jumps)

-- --- 6. CC re-enabled by game → disabled again
P.cc.enabled = true; frame()
check("CC kept disabled", P.cc.enabled == false)

-- --- 7. fall info reset every frame while flying
local r = P.fall.resets; frame(); frame()
check("FallInfo reset while flying", P.fall.resets >= r + 2)

-- --- 8. game teleport (ferrystone etc.) is followed
s = P.model
P.hist = P.hist + vec(1000, 0, 0); P.xpos = P.hist
frame(); frame()
check("big game teleport followed", approx(P.model.x, s.x + 1000), vstr(P.model))

-- --- 9. menu open: no movement, game input untouched
uiOpen = true; s = P.model; walked = P.walked; moveFrame({ 0x57 }); moveFrame({ 0x57 }); uiOpen = false
check("no fly movement while menu open", approx((P.model - s):length(), 0), vstr(P.model - s))
check("game input still suppressed while menu open", P.walked == walked, P.walked - walked)

-- --- 10. safe landing from height
for i = 1, 30 do moveFrame({ 0x20 }) end                     -- climb ~36m
local h = P.model.y
check("climbed high", h > 30, h)
local warps = P.cc.warps
keys[0x75] = true; frame(); keys[0x75] = nil; drawUI()
check("F6 disables fly", statusText() == "状态：关闭", statusText())
check("CC re-enabled", P.cc.enabled == true)
check("CC warp on disable", P.cc.warps > warps)
for i = 1, 40 do frame() end                                  -- fall to ground
check("falls to ground after off", approx(P.model.y, GROUND_Y), P.model.y)
check("no fall damage with safe landing", P.damage == 0, P.damage)

-- --- 11. without safe landing: damage happens (protection really does something)
fly(true)
for i = 1, 30 do moveFrame({ 0x20 }) end
ui.checkbox["关闭后 10 秒内防摔伤"] = false; drawUI()
fly(false)
for i = 1, 40 do frame() end
check("fall damage when protection off", P.damage > 0, P.damage)
ui.checkbox["关闭后 10 秒内防摔伤"] = true; drawUI()
P.damage = 0

-- --- 12. after off, game controls work again
walked, jumps = P.walked, P.jumps
moveFrame({ 0x57, 0x20 })
check("game walk works after off", P.walked == walked + 1)
check("game jump works after off", P.jumps == jumps + 1)

-- --- 13. UI checkbox + original CC state preserved
fly(true); check("UI checkbox enables", statusText() == "状态：开启", statusText())
fly(false); check("UI checkbox disables", statusText() == "状态：关闭" and P.cc.enabled == true)
P.cc.enabled = false; fly(true); fly(false)
check("original CC disabled state restored", P.cc.enabled == false)
P.cc.enabled = true

-- --- 14. player change → auto off, old CC restored
fly(true)
local old = P
currentPlayer = newPlayer(0x2000); P = currentPlayer
frame(); drawUI()
check("player change auto-disables", statusText():find("自动关闭") ~= nil, statusText())
check("old player's CC restored", old.cc.enabled == true)
check("new player's CC untouched", P.cc.enabled == true)

-- --- 15. no player
currentPlayer = nil; fly(true)
check("enable without player fails gracefully", statusText():find("未进入游戏") ~= nil, statusText())
currentPlayer = P; frame()

-- --- 16. no CC component
currentPlayer = newPlayer(0x3000, { noCC = true }); P = currentPlayer; frame()
fly(true)
check("no CC -> warning", statusText():find("未找到碰撞组件") ~= nil, statusText())
s = P.model; moveFrame({ 0x20 })
check("no CC -> movement still works", approx(P.model.y, s.y + 1.2), vstr(P.model - s))
fly(false)

-- --- 17. warp unavailable → fallback + revert warning (old bug surfaces as warning, not silence)
currentPlayer = newPlayer(0x4000, { warpBroken = true }); P = currentPlayer; frame()
fly(true)
for i = 1, 30 do moveFrame({ 0x20 }) end
drawUI()
check("warp missing -> revert is detected and reported", statusText():find("拉回") ~= nil, statusText())
fly(false)

-- --- 18. runtime error inside tick is contained
currentPlayer = newPlayer(0x5000); P = currentPlayer; frame()
fly(true)
P.throwOnWarp = true
local okf = pcall(frame); drawUI()
check("warp error doesn't crash", okf)
P.throwOnWarp = false
fly(false); fly(true)
s = P.model; moveFrame({ 0x20 })
check("still works after error", approx(P.model.y, s.y + 1.2), vstr(P.model - s))
fly(false)

-- --- 19. input hook unavailable → UpdateBehavior fallback still moves the model
hookAvailable = false
currentPlayer = newPlayer(0x6000); P = currentPlayer
loadScript()
check("no hook installed when method missing", #hooks == 0)
frame(); fly(true)
s = P.model; for i = 1, 5 do moveFrame({ 0x20 }) end
check("fallback path moves model", approx(P.model.y, s.y + 6), vstr(P.model - s))
fly(false)
hookAvailable = true
loadScript()

-- ===================== Kill all =====================
local function killStatus()
  local n = 0
  for _, t in ipairs(ui.texts) do if t:find("^状态") then n = n + 1; if n == 2 then return t end end end
  return ""
end
local function E(name) for _, e in ipairs(enemies) do if e.name == name then return e end end end
local function pressF7() keys[0x76] = true; frame(); frame(); keys[0x76] = nil; frame(); end
local function settle() for i = 1, 8 do frame() end drawUI() end       -- > confirmDelay (0.5s)
local function countLog(pat) local n = 0 for _, l in ipairs(logLines) do if l:find(pat) then n = n + 1 end end return n end
currentPlayer = newPlayer(0x8000); P = currentPlayer; frame()

-- K0 the real in-game bug: collection without get_Item (and no other accessor) → clear failure, no spam
listShape = "none"
enemies = { newEnemy("goblin", 300, 10) }
logLines = {}
pressF7(); pressF7(); pressF7(); drawUI()
check("unreadable list: no crash + clear status", killStatus():find("敌人列表读取失败") ~= nil, killStatus())
check("unreadable list: failure logged once", countLog("unreadable") == 1, countLog("unreadable"))

-- K1 every collection shape works (Dark Arisen list has no get_Item)
for _, shape in ipairs({ "ToArray", "_items", "_entries", "get_elements", "get_Item" }) do
  listShape = shape
  enemies = { newEnemy("goblin", 300, 10), newEnemy("dragon", 90000, 900, { boss = true }), newEnemy("corpse", 0, 5) }
  pressF7(); settle()
  check("[" .. shape .. "] goblin killed", E("goblin").dead)
  check("[" .. shape .. "] far boss dragon killed", E("dragon").dead)
  check("[" .. shape .. "] each enemy processed once", E("goblin").sets == 1 and E("dragon").sets == 1, E("goblin").sets)
  check("[" .. shape .. "] corpse untouched", E("corpse").sets == 0 and not E("corpse").revived)
end
listShape = "ToArray"

-- K2 HP 0 doesn't kill → killAndSetDieLoop finishes them after confirm delay
hp0Kills = false
enemies = { newEnemy("ogre", 5000, 20), newEnemy("griffin", 40000, 60, { boss = true }) }
pressF7(); drawUI()
check("hp0-alive: HP zeroed first", E("ogre").hp == 0 and not E("ogre").dead)
check("hp0-alive: status says confirming", killStatus():find("确认中") ~= nil, killStatus())
settle()
check("hp0-alive: ogre finished by killAndSetDieLoop", E("ogre").dead and E("ogre").kills == 1)
check("hp0-alive: boss finished by killAndSetDieLoop", E("griffin").dead and E("griffin").kills == 1)
check("hp0-alive: status reports forced kills", killStatus():find("2 个用游戏击杀函数补刀") ~= nil, killStatus())
hp0Kills = true
enemies = { newEnemy("rat", 50, 5) }
pressF7(); settle()
check("hp0-kills: no extra killAndSetDieLoop", E("rat").dead and E("rat").kills == 0)
check("hp0-kills: status reports HP-0 deaths", killStatus():find("1 个 HP 归零即死亡") ~= nil, killStatus())

-- K3 story no-die protection: skipped by default, forced with checkbox
enemies = { newEnemy("scripted_boss", 80000, 30, { boss = true, noDie = true }), newEnemy("minion", 200, 10) }
pressF7(); settle()
check("no-die boss skipped by default", not E("scripted_boss").dead and E("scripted_boss").hp == 80000)
check("minion still killed", E("minion").dead)
pressF7(); drawUI()
check("status mentions protected count", killStatus():find("1 个受剧情不死保护") ~= nil, killStatus())
ui.checkbox["强制：无视剧情不死保护（可能卡剧情，先存档）"] = true; drawUI()
pressF7(); settle()
check("forced: no-die boss killed", E("scripted_boss").dead and not E("scripted_boss").noDie)
ui.checkbox["强制：无视剧情不死保护（可能卡剧情，先存档）"] = false; drawUI()

-- K4 broken enemy isolated, logged once
enemies = { newEnemy("ok1", 300, 10), newEnemy("broken", 500, 20, { broken = true }), newEnemy("ok2", 300, 30) }
logLines = {}
pressF7(); settle(); pressF7(); settle()
check("broken enemy doesn't stop others", E("ok1").dead and E("ok2").dead and not E("broken").dead)
check("same error logged once", countLog("enemy #%d error") == 1, countLog("enemy #%d error"))

-- K5 range filter
enemies = { newEnemy("near", 300, 10), newEnemy("far", 300, 80), newEnemy("farboss", 50000, 200, { boss = true }) }
imgui.slider_float = function(l, v) if l:find("^范围") then return true, 50.0 end return false, v end
ui.clicks["秒杀全场（含 BOSS）"] = true; drawUI(); ui.clicks = {}; frame(); settle()
imgui.slider_float = function(l, v) if l:find("^范围") then return true, 0.0 end return false, v end
drawUI(); imgui.slider_float = function(_, v) return false, v end
check("range 50m: near killed", E("near").dead)
check("range 50m: far spared", not E("far").dead and E("far").sets == 0)
check("range 50m: far boss spared", not E("farboss").dead)

-- K6 one-hit mode (F8)
enemies = { newEnemy("orc", 800, 15), newEnemy("cyclops", 30000, 60, { boss = true }), newEnemy("deadguy", 0, 5),
            newEnemy("guarded", 9000, 20, { noDie = true }) }
keys[0x77] = true; frame(); keys[0x77] = nil; frame(); drawUI()
check("F8 enables one-hit", killStatus():find("一击必杀：开启") ~= nil, killStatus())
check("one-hit caps orc HP to 1", E("orc").hp == 1 and not E("orc").dead)
check("one-hit caps boss HP to 1", E("cyclops").hp == 1 and not E("cyclops").dead)
check("one-hit never revives corpse", E("deadguy").sets == 0 and not E("deadguy").revived)
check("one-hit skips no-die by default", E("guarded").hp == 9000)
hitEnemy(E("orc"), 5); hitEnemy(E("cyclops"), 5)
check("any hit kills capped enemies", E("orc").dead and E("cyclops").dead)
table.insert(enemies, newEnemy("newspawn", 600, 30))
for i = 1, 6 do frame() end
check("new spawn gets capped", E("newspawn").hp == 1)
local setsBefore = E("orc").sets
for i = 1, 10 do frame() end
check("dead enemies not touched again", E("orc").sets == setsBefore and not E("orc").revived)
E("newspawn").hp = 5000
for i = 1, 6 do frame() end
check("healed/phase-2 enemy recapped", E("newspawn").hp == 1)
local s0 = E("newspawn").sets; E("newspawn").hp = 100; frame(0.1); local s1 = E("newspawn").sets
check("one-hit pass throttled (≈0.5s)", s1 - s0 <= 1)
keys[0x77] = true; frame(); keys[0x77] = nil; frame(); drawUI()
check("F8 disables one-hit", killStatus() == "状态：一击必杀：关闭", killStatus())
E("newspawn").hp = 900; for i = 1, 10 do frame() end
check("after off, HP no longer capped", E("newspawn").hp == 900)

-- K7 UI checkbox for one-hit
ui.checkbox["一击必杀模式（持续把敌人 HP 压到 1）"] = true; drawUI(); frame(); drawUI()
check("UI checkbox enables one-hit", E("newspawn").hp == 1, E("newspawn").hp)
ui.checkbox["一击必杀模式（持续把敌人 HP 压到 1）"] = false; drawUI(); frame()

-- K8 one-hit with unreadable list: no log spam (the 2100-line bug)
listShape = "none"; logLines = {}
ui.checkbox["一击必杀模式（持续把敌人 HP 压到 1）"] = true; drawUI()
for i = 1, 60 do frame() end
check("one-hit unreadable list logged once (no spam)", countLog("unreadable") <= 1, countLog("unreadable"))
ui.checkbox["一击必杀模式（持续把敌人 HP 压到 1）"] = false; drawUI(); frame()
listShape = "ToArray"

-- K9 no EnemyManager (title screen)
enemyManagerPresent = false
ui.clicks["秒杀全场（含 BOSS）"] = true; drawUI(); ui.clicks = {}
local okK = pcall(frame); drawUI()
check("no EnemyManager: no crash", okK)
check("no EnemyManager: clear status", killStatus():find("EnemyManager") ~= nil, killStatus())
enemyManagerPresent = true

-- K10 diagnostics (runs on game thread)
enemies = { newEnemy("goblin", 300, 10), newEnemy("medusa", 40000, 120, { boss = true, noDie = true }) }
os.remove("DD2_HitMethods.txt")
ui.clicks["诊断：导出敌人列表与 HP/伤害相关方法"] = true; drawUI(); ui.clicks = {}
check("diag deferred to game thread", io.open("DD2_HitMethods.txt") == nil)
frame(); drawUI()
local df = io.open("DD2_HitMethods.txt"); local dump = df and df:read("a") or ""; if df then df:close() end
check("diag file written", dump ~= "", killStatus())
check("diag: HitController methods", dump:find("setHpValue%(System.Single, System.Boolean%)") ~= nil)
check("diag: killAndSetDieLoop listed", dump:find("killAndSetDieLoop%(app.Character.KillAndSetDieLoopOption%)") ~= nil)
check("diag: EnemyManager methods (unfiltered)", dump:find("getAllEnemies%(%)") ~= nil and dump:find("get_EnemyCount") ~= nil)
check("diag: kill option enum fields", dump:find("None = 0") ~= nil and dump:find("parent=System.Enum") ~= nil, dump)
check("diag: list type + count + via", dump:find("count=2") and dump:find("via=ToArray"), dump)
check("diag: per-enemy line with id/HP/NoDie", dump:find("CharaIDString=medusa") and dump:find("IsNoDie=true") and dump:find("Hp=40000"), dump)
check("diag: filters unrelated Character methods", not dump:find("warp%("))

-- K11 cross-feature: kill while flying
enemies = { newEnemy("bandit", 400, 25) }
fly(true)
s = P.model; moveFrame({ 0x20 })
pressF7(); settle()
check("kill works while flying", E("bandit").dead)
s = P.model; moveFrame({ 0x20 })
check("fly still works after kill", approx(P.model.y, s.y + 1.2))
fly(false)

-- ===================== Regression: item features =====================
currentPlayer = newPlayer(0x7000); P = currentPlayer; frame()
ui.clicks["导出全物品清单（CSV/JSON）"] = true; drawUI(); ui.clicks = {}
for i = 1, 30 do frame() end
local f = io.open("DD2_ItemList.csv"); local csv = f and f:read("a") or ""; if f then f:close() end
check("item export still works (3 items)", select(2, csv:gsub("\n", "")) == 4, csv)
check("item names resolved", csv:find("名%-g4999") ~= nil)
local oldInput, oldDrag = imgui.input_text, imgui.drag_int
imgui.input_text = function(l, v) if l == "物品ID" then return true, "10" end return false, v end
imgui.drag_int = function(l, v) return true, 5 end
given = {}
ui.clicks["添加到背包"] = true; drawUI(); ui.clicks = {}; frame()
check("give item still works", #given == 1 and given[1][1] == 10 and given[1][2] == 5, #given)
fly(true)
ui.clicks["添加到背包"] = true; drawUI(); ui.clicks = {}; frame()
check("give item works while flying", #given == 2, #given)
s = P.model; moveFrame({ 0x20 })
check("fly works after giving item", approx(P.model.y, s.y + 1.2))
fly(false)
imgui.input_text, imgui.drag_int = oldInput, oldDrag

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
