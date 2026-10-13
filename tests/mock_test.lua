-- 模拟 REFramework 运行时的离线测试（不需要游戏）
-- 用法: lua tests/mock_test.lua reframework/autorun/DD2_ItemSpawner.lua
-- ===== Mock REFramework runtime =====
local SCRIPT = arg[1]
local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (extra and ("  -- " .. extra) or "")) end
end
local function approx(a, b, eps) return math.abs(a - b) < (eps or 1e-4) end

-- Vector3f
local V = {}; V.__index = V
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return vec(a.x * b, a.y * b, a.z * b) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:normalized() local l = self:length(); return vec(self.x / l, self.y / l, self.z / l) end
function V:to_vec3() return vec(self.x, self.y, self.z) end
Vector3f = { new = vec }
local function vstr(v) return string.format("(%.3f,%.3f,%.3f)", v.x, v.y, v.z) end

-- camera (yaw in radians; RE camera looks -Z)
local camYaw = 0
local function camMatrix()
  local c, s = math.cos(camYaw), math.sin(camYaw)
  -- rotation around Y: X axis, Y axis, Z axis rows
  return { [0] = vec(c, 0, -s), [1] = vec(0, 1, 0), [2] = vec(s, 0, c), [3] = vec(0, 0, 0) }
end

-- player world
local function newCC() return { enabled = true, warps = 0 } end
local function newPlayer(addr, withCC)
  local p = { addr = addr, pos = vec(100, 50, 200), setCount = 0, throwOnSet = false, cc = withCC and newCC() or nil }
  local xform = {}
  function xform.get_Position(self) return vec(p.pos.x, p.pos.y, p.pos.z) end
  function xform.set_Position(self, v) if p.throwOnSet then error("boom") end p.pos = vec(v.x, v.y, v.z); p.setCount = p.setCount + 1 end
  local ccObj = p.cc and {
    call = function(self, sig, ...)
      if sig == "get_Enabled" then return p.cc.enabled end
      if sig == "set_Enabled" then p.cc.enabled = ...; return end
      if sig == "warp" then p.cc.warps = p.cc.warps + 1; return end
    end } or nil
  local go = {
    get_Transform = function() return xform end,
    call = function(self, sig, t) if sig == "getComponent(System.Type)" then return ccObj end end,
  }
  p.obj = { get_GameObject = function() return go end, get_address = function() return addr end, get_CharaID = function() return 1 end }
  return p
end
local P = newPlayer(0x1000, true)
local currentPlayer = P

-- keyboard / ui
local keys = {}
local uiOpen = false
reframework = { is_key_down = function(self, k) return keys[k] == true end, is_drawing_ui = function() return uiOpen end }

-- clock
local clockT = 0
os.clock = function() return clockT end

-- item manager mocks
local itemData, given = {}, {}
for _, id in ipairs({ 3, 10, 4999 }) do
  itemData[id] = { get_type_definition = function() return {
      get_name = function() return "ItemCommonParam" end, get_full_name = function() return "app.ItemCommonParam" end,
      get_fields = function() return { { get_type = function() return { get_full_name = function() return "System.Guid" end } end,
        is_static = function() return false end, get_name = function() return "_NameMsgId" end } } end,
      get_parent_type = function() return nil end } end,
    get_field = function(_, f) return "g" .. id end }
end
local mgr = {}
sdk = {
  find_type_definition = function(n)
    return { get_method = function(_, sig) return { is_static = function() return true end, call = function(self, this, ...)
      if sig == "getItemData(System.Int32)" then return itemData[...] end
      if sig:find("^getItem%(") then table.insert(given, { ... }) return true end
      if sig == "get(System.Guid)" then return "名-" .. tostring(...) end end } end }
  end,
  get_managed_singleton = function(n)
    if n == "app.CharacterManager" then return { call = function(self, sig) return currentPlayer and currentPlayer.obj end } end
    return mgr
  end,
  get_primary_camera = function() return { get_GameObject = function() return { get_Transform = function() return { get_WorldMatrix = function() return camMatrix() end } end } end } end,
  typeof = function(n) return n end,
}
ValueType = { new = function() return {} end }
log = { info = function(s) io.write("      log: ", s, "\n") end }
json = { load_file = function() return nil end, dump_file = function() end }

local cb = { post = {}, pre = {} }
re = {
  on_application_entry = function(n, f) cb.post[n] = f end,
  on_pre_application_entry = function(n, f) cb.pre[n] = f end,
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

dofile(SCRIPT)

local function frame(dt)
  clockT = clockT + (dt or 0.1)
  cb.post.UpdateBehavior()
  cb.post.LateUpdateBehavior()
  cb.pre.BeginRendering()
end
local function drawUI() ui.texts = {}; cb.ui() end
local function statusText() for _, t in ipairs(ui.texts) do if t:find("^状态") then return t end end end

-- ===== Tests =====
check("callbacks registered", cb.post.UpdateBehavior and cb.post.LateUpdateBehavior and cb.pre.BeginRendering and cb.ui)

-- 1 toggle on via F6, edge only
keys[0x75] = true; frame(); frame(); frame()
drawUI()
check("F6 enables fly", statusText() == "状态：开启", statusText())
check("CharacterController disabled", P.cc.enabled == false)
keys[0x75] = nil; frame()
check("holding F6 does not re-toggle", statusText() == "状态：开启")

-- 2 no input: hold position against external drift (gravity)
local start = P.pos
for i = 1, 5 do P.pos = P.pos + vec(0, -0.5, 0); frame() end
check("holds position against gravity drift", approx(P.pos.y, start.y) and approx(P.pos.x, start.x), vstr(P.pos))

-- 3 W along camera forward (-Z at yaw 0), speed 12 m/s, dt 0.1 => 1.2m/frame
local s = P.pos; keys[0x57] = true; frame(0.1); keys[0x57] = nil
check("W moves 1.2m along -Z", approx(P.pos.z, s.z - 1.2) and approx(P.pos.x, s.x), vstr(P.pos - s))
s = P.pos; keys[0x53] = true; frame(0.1); keys[0x53] = nil
check("S moves 1.2m along +Z", approx(P.pos.z, s.z + 1.2), vstr(P.pos - s))
s = P.pos; keys[0x44] = true; frame(0.1); keys[0x44] = nil
check("D moves along +X", approx(P.pos.x, s.x + 1.2), vstr(P.pos - s))
s = P.pos; keys[0x41] = true; frame(0.1); keys[0x41] = nil
check("A moves along -X", approx(P.pos.x, s.x - 1.2), vstr(P.pos - s))
s = P.pos; keys[0x20] = true; frame(0.1); keys[0x20] = nil
check("Space rises", approx(P.pos.y, s.y + 1.2), vstr(P.pos - s))
s = P.pos; keys[0xA2] = true; frame(0.1); keys[0xA2] = nil
check("LCtrl descends", approx(P.pos.y, s.y - 1.2), vstr(P.pos - s))
s = P.pos; keys[0x57] = true; keys[0x10] = true; frame(0.1); keys[0x57] = nil; keys[0x10] = nil
check("Shift x4 speed", approx(P.pos.z, s.z - 4.8), vstr(P.pos - s))
s = P.pos; keys[0x57] = true; keys[0x44] = true; frame(0.1); keys[0x57] = nil; keys[0x44] = nil
check("diagonal normalized (length 1.2)", approx((P.pos - s):length(), 1.2), vstr(P.pos - s))

-- 4 camera yaw 90deg: forward = -( sin, 0, cos ) = (-1,0,0)
camYaw = math.pi / 2
s = P.pos; keys[0x57] = true; frame(0.1); keys[0x57] = nil
check("W follows camera yaw", approx(P.pos.x, s.x - 1.2) and approx(P.pos.z, s.z), vstr(P.pos - s))
camYaw = 0

-- 5 dt clamp
s = P.pos; keys[0x57] = true; frame(5.0); keys[0x57] = nil
check("dt clamped to 0.1s", approx((P.pos - s):length(), 1.2), vstr(P.pos - s))

-- 6 game re-enables CC -> disabled again
P.cc.enabled = true; frame()
check("CC kept disabled if game re-enables", P.cc.enabled == false)

-- 7 teleport / origin rebase follow
s = P.pos; P.pos = P.pos + vec(1000, 0, 0); frame()
check("big external jump is followed, not reverted", approx(P.pos.x, s.x + 1000), vstr(P.pos))

-- 8 UI open blocks movement
uiOpen = true; s = P.pos; keys[0x57] = true; frame(0.1); keys[0x57] = nil; uiOpen = false
check("no movement while REFramework menu open", approx((P.pos - s):length(), 0), vstr(P.pos - s))

-- 9 BeginRendering re-locks after root-motion style write
s = P.pos; cb.post.LateUpdateBehavior(); P.pos = P.pos + vec(0.3, 0, 0); cb.pre.BeginRendering()
check("BeginRendering re-applies target", approx((P.pos - s):length(), 0), vstr(P.pos - s))

-- 10 toggle off with F6: restore CC + warp
local warps = P.cc.warps
keys[0x75] = true; frame(); keys[0x75] = nil; frame()
drawUI()
check("F6 again disables fly", statusText() == "状态：关闭", statusText())
check("CC re-enabled", P.cc.enabled == true)
check("CC warp called on disable", P.cc.warps == warps + 1)
s = P.pos; P.pos = P.pos + vec(0, -1, 0); frame()
check("after off, position no longer locked", approx(P.pos.y, s.y - 1))

-- 11 UI checkbox on/off
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame(); drawUI()
check("UI checkbox enables", statusText() == "状态：开启", statusText())
ui.checkbox["启用穿墙飞天"] = false; drawUI(); frame(); drawUI()
check("UI checkbox disables", statusText() == "状态：关闭" and P.cc.enabled == true, statusText())

-- 12 CC originally disabled stays disabled after off
P.cc.enabled = false
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame()
ui.checkbox["启用穿墙飞天"] = false; drawUI(); frame()
check("original CC disabled state restored", P.cc.enabled == false)
P.cc.enabled = true

-- 13 player change -> auto off, old CC restored
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame()
local old = P
currentPlayer = newPlayer(0x2000, true); P = currentPlayer
frame(); drawUI()
check("player change auto-disables", statusText():find("自动关闭") ~= nil, statusText())
check("old player's CC restored", old.cc.enabled == true)
check("new player's CC untouched", P.cc.enabled == true)

-- 14 no player
currentPlayer = nil
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame(); drawUI()
check("enable without player fails gracefully", statusText():find("未进入游戏") ~= nil, statusText())
currentPlayer = P

-- 15 player without CC
currentPlayer = newPlayer(0x3000, false); P = currentPlayer
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame(); drawUI()
check("no CC -> still flies with warning", statusText():find("未找到碰撞组件") ~= nil, statusText())
s = P.pos; keys[0x20] = true; frame(0.1); keys[0x20] = nil
check("no CC -> movement works", approx(P.pos.y, s.y + 1.2))
ui.checkbox["启用穿墙飞天"] = false; drawUI(); frame()

-- 16 exception in set_Position is contained
currentPlayer = newPlayer(0x4000, true); P = currentPlayer
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame()
P.throwOnSet = true
local ok = pcall(frame); drawUI()
check("set_Position error does not crash script", ok)
P.throwOnSet = false
ui.checkbox["启用穿墙飞天"] = false; drawUI(); frame()
check("can turn off after error", P.cc.enabled == true)

-- ===== Regression: item features =====
ui.clicks["导出全物品清单（CSV/JSON）"] = true; drawUI(); ui.clicks = {}
for i = 1, 30 do frame() end
local f = io.open("DD2_ItemList.csv"); local csv = f and f:read("a") or ""; if f then f:close() end
check("item export still works (3 items)", select(2, csv:gsub("\n", "")) == 4, csv)
check("item names resolved", csv:find("名%-g4999") ~= nil)
-- give item via search + button (mock the input text by setting through ID box is not reachable; call queue via button with ID)
imgui.input_text = function(l, v) if l == "物品ID" then return true, "10" end return false, v end
imgui.drag_int = function(l, v) return true, 5 end
ui.clicks["添加到背包"] = true; drawUI(); ui.clicks = {}; frame()
check("give item still works", #given == 1 and given[1][1] == 10 and given[1][2] == 5, tostring(#given))
-- give item while flying
ui.checkbox["启用穿墙飞天"] = true; drawUI(); frame()
ui.clicks["添加到背包"] = true; drawUI(); ui.clicks = {}; frame()
check("give item works while flying", #given == 2)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
