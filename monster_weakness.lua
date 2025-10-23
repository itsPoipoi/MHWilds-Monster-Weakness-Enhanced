-- By RedBeanN, enhancements by Poïpoï (using GitHub Copilot)
-- Shows monster part weaknesses in a table during quests.
-- Features:
-- - Auto-hide after a configurable timeout, reset on quest start or hotkey press
-- - Option to use Reframework font size or custom font size
-- - Option to toggle table visibility with a rebindable hotkey
-- - More colors depending on weakness values
-- Great thanks to lingsamuel for CatLib and other codes.
local re = re
local sdk = sdk
local d2d = d2d
local imgui = imgui
local log = log
local json = json
local draw = draw
local require = require
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local math = math
local string = string
local table = table
local type = type
local thread = thread

local Core = require("_CatLib")
local CONST = require("_CatLib.const")
local FontUtils = require("_CatLib.font")
local Utils = require("_CatLib.utils")
local Imgui = require("_CatLib.imgui")

local lineheight = 24
local EnemyContext_Parts = Core.TypeField("app.cEnemyContext", "Parts")

local CommonText = {
  TableName = "Monster Weakness",
  ConfigureName = "Table Configurations",
  UseRefFont = "Use Reframework Font Size",
  ConfAutoHide = "Auto Hide",
  ConfHideAfter = "Hide After (seconds)",
  UseHotkey = "Use Hotkey To Toggle Table",
  HotkeySettings = "Hotkey Settings",
  HotkeyBindText = "Press a key to bind (ESC to cancel)",
  HotkeyBindButton = "Bind Hotkey"
}

local mod = Core.NewMod("Monster Weakness")
local CONF = mod.ModName.."/monster_weakness.json"
local customConf = mod.LoadConfig(CONF)
local FontSizeOptions = { "14", "16", "18", "20", "24", "28", "32", "36", "40", "44", "48" }

-- add key name map and binding state
local key_names = {
  [0x01] = "LButton", [0x02] = "RButton", [0x03] = "MButton", [0x04] = "XButton1", [0x05] = "XButton2",
  [0x08] = "Back", [0x09] = "Tab", [0x0D] = "Enter", [0x10] = "Shift", [0x11] = "Ctrl",
  [0x12] = "Alt", [0x14] = "CapsLock", [0x1B] = "Esc", [0x20] = "Space",
  [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
  [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
  [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
  [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E",
  [0x46] = "F", [0x47] = "G", [0x48] = "H", [0x49] = "I", [0x4A] = "J",
  [0x4B] = "K", [0x4C] = "L", [0x4D] = "M", [0x4E] = "N", [0x4F] = "O",
  [0x50] = "P", [0x51] = "Q", [0x52] = "R", [0x53] = "S", [0x54] = "T",
  [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X", [0x59] = "Y",
  [0x5A] = "Z",
  [0x60] = "Num0", [0x61] = "Num1", [0x62] = "Num2", [0x63] = "Num3", [0x64] = "Num4",
  [0x65] = "Num5", [0x66] = "Num6", [0x67] = "Num7", [0x68] = "Num8", [0x69] = "Num9",
  [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5",
  [0x75] = "F6", [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10",
  [0x7A] = "F11", [0x7B] = "F12",
  -- OEM / punctuation
  [0xBA] = ";:", [0xBB] = "=+", [0xBC] = ",<", [0xBD] = "-_", [0xBE] = ".>",
  [0xBF] = "/?", [0xC0] = "`~", [0xDB] = "[{", [0xDC] = "\\|", [0xDD] = "]}",
  [0xDE] = "'\""
}
local is_binding_hotkey = false

local function NewCustomConf()
  return {
    UseRefFont = true,
    FontSize = 18,
    AutoHide = true,
    HideAfter = 60,
    UseHotkey = false,
    Hotkey = {
      key = 0xDE, -- default key (same as original)
      ctrl = false,
      alt = false,
      shift = false
    }
  }
end
local function InitConf()
  local confChanged = false
  customConf = Utils.MergeTablesRecursive(NewCustomConf(), customConf)
  mod.Config.CustomConfig = customConf
  mod.SaveConfig()
end
InitConf()

local function indexOf(arr, val)
  for i, v in ipairs(arr) do
    if v == val then return i
    end
  end
  return -1
end

-- Replace the submenu UI with main mod configuration UI so it appears between Enabled and Debug
mod.Menu(function()
  local configChanged = false
  local changed = false
  local conf = customConf

  -- ensure Hotkey has proper structure (fix corrupt/old configs where Hotkey may be a number)
  if type(conf.Hotkey) ~= "table" then
    conf.Hotkey = {
      key = 0xDE,
      ctrl = false,
      alt = false,
      shift = false
    }
    configChanged = true
  end

  changed, conf.UseRefFont = imgui.checkbox(CommonText.UseRefFont, conf.UseRefFont)
  configChanged = configChanged or changed
  if not conf.UseRefFont then
    local fzIndex = indexOf(FontSizeOptions, tostring(conf.FontSize))
    changed, fzIndex = imgui.combo("Font Size", fzIndex, FontSizeOptions)
    if changed then
      conf.FontSize = tonumber(FontSizeOptions[fzIndex])
    end
    configChanged = configChanged or changed
  end

  changed, conf.UseHotkey = imgui.checkbox(CommonText.UseHotkey, conf.UseHotkey)
  configChanged = configChanged or changed
  if conf.UseHotkey then
    -- Hotkey binding UI
    local hotkeyTreeOpened = imgui.tree_node(CommonText.HotkeySettings)
    if hotkeyTreeOpened then
      if is_binding_hotkey then
        imgui.text(CommonText.HotkeyBindText)
        if reframework:is_key_down(0x1B) then -- ESC to cancel
          is_binding_hotkey = false
        else
          -- scan all virtual-key codes so any VK can be bound (use VK codes)
          for key = 1, 254 do
            if key ~= 0x10 and key ~= 0x11 and key ~= 0x12 then
              if reframework:is_key_down(key) then
                conf.Hotkey.key = key
                is_binding_hotkey = false
                configChanged = true
                break
              end
            end
          end
        end
      else
        local keyLabel = key_names[conf.Hotkey.key] or ("0x" .. string.format("%X", conf.Hotkey.key))
        if imgui.button(CommonText.HotkeyBindButton .. ": " .. keyLabel) then
          is_binding_hotkey = true
        end
      end

      changed, conf.Hotkey.ctrl = imgui.checkbox("Ctrl", conf.Hotkey.ctrl)
      configChanged = configChanged or changed
      changed, conf.Hotkey.alt = imgui.checkbox("Alt", conf.Hotkey.alt)
      configChanged = configChanged or changed
      changed, conf.Hotkey.shift = imgui.checkbox("Shift", conf.Hotkey.shift)
      configChanged = configChanged or changed
    end

    if hotkeyTreeOpened then imgui.tree_pop() end

    -- AutoHide still allowed while using hotkey
    changed, conf.AutoHide = imgui.checkbox(CommonText.ConfAutoHide, conf.AutoHide)
    configChanged = configChanged or changed
    if conf.AutoHide then
      changed, conf.HideAfter = imgui.slider_int(CommonText.ConfHideAfter, conf.HideAfter, 5, 180)
      configChanged = configChanged or changed
    end
  else
    -- original behavior when not using hotkey: auto-hide controls
    changed, conf.AutoHide = imgui.checkbox(CommonText.ConfAutoHide, conf.AutoHide)
    configChanged = configChanged or changed
    if conf.AutoHide then
      changed, conf.HideAfter = imgui.slider_int(CommonText.ConfHideAfter, conf.HideAfter, 5, 180)
      configChanged = configChanged or changed
    end
  end

  customConf = conf
  if configChanged then
    mod.SaveConfig(CONF, customConf)
  end
  return configChanged
end)

local enabled = false
local tables = {}

local scriptRunTime = 0
local lastLoadTime = scriptRunTime

local GetMeatFunc = sdk.find_type_definition("app.user_data.EmParamParts"):get_method("getMeatIndex(System.Guid)")
local GetPartsFunc = sdk.find_type_definition("app.user_data.EmParamParts"):get_method("getLinkPartsIndexByBreakPartsIndex(System.Int32)")
local GetPartsByGuidFunc = sdk.find_type_definition("app.user_data.EmParamParts"):get_method("getPartsIndex(System.Guid)")
local NullableInt32_HasValue = Core.TypeField("System.Nullable`1<System.Int32>", "_HasValue")
local NullableInt32_Value = Core.TypeField("System.Nullable`1<System.Int32>", "_Value")

local function LoadEm()
  lastLoadTime = scriptRunTime

  local isQuest = Core.IsActiveQuest()
  local quest = Core.GetMissionManager()._QuestDirector
  if not quest then return end
  local emData = quest:getQuestTargetEmBrowsers()
  if not emData then return end

  local loaded = {}
  if (isQuest) then
    local browsers = Core.GetMissionManager():getAcceptQuestTargetBrowsers()
    if browsers then
      Core.ForEach(browsers, function (browser)
        local ctx = browser:get_EmContext()
        local my_table = {
          Title = Core.GetEnemyName(ctx:get_EmID()),
          Rows = {}
        }
        if loaded[my_table.Title] then return end
        loaded[my_table.Title] = my_table
        local isBoss = ctx:get_IsBoss()
        if not isBoss then return end
        local params = ctx.Parts._ParamParts
        if not params then return end
        if not params._MeatArray then return end
        local meats = params._MeatArray._DataArray
        if not meats then return end
        local parts = params._PartsArray._DataArray
        if not parts then return end

        local weakPoints = params._WeakPointArray._DataArray
        local weakPartMap = {}
        Core.ForEach(weakPoints, function (point, index)
          local bI = GetMeatFunc:call(params, point._MeatGuid)
          if not NullableInt32_HasValue:get_data(bI) then return end
          local breakIndex = NullableInt32_Value:get_data(bI)
          -- log.debug("Weakpoint has meat " .. breakIndex)
          local breakMeat = meats[breakIndex]
          if not breakMeat then return end
          local linkPart = GetPartsFunc:call(params, index)
          -- log.debug("link parts num " .. #linkPart)
          for i, id in pairs(linkPart) do
            local partIndex = id:get_field('m_value')
            weakPartMap[partIndex] = breakMeat
          end
        end)
  
        local scarPoints = params._ScarPointArray._DataArray
        local scarPointsMap = {}
        Core.ForEach(scarPoints, function (point, index)
          local bI = GetMeatFunc:call(params, point._MeatGuid)
          if not NullableInt32_HasValue:get_data(bI) then return end
          local scarIndex = NullableInt32_Value:get_data(bI)
          local scarMeat = meats[scarIndex]
          if not scarMeat then return end
          local linkPart = GetPartsByGuidFunc:call(params, point._LinkPartsGuid)
          if not NullableInt32_HasValue:get_data(linkPart) then return end
          local partIndex = NullableInt32_Value:get_data(linkPart)
          scarPointsMap[partIndex] = scarMeat
        end)

        Core.ForEach(parts, function (part, index)
          local meat = meats[index]
          local partType = Core.FixedToEnum("app.EnemyDef.PARTS_TYPE", part._PartsType._Value)
          if not partType then return end
          if part then
            local mI = GetMeatFunc:call(params, part._MeatGuidNormal)
            if NullableInt32_HasValue:get_data(mI) then
              local realIndex = NullableInt32_Value:get_data(mI)
              meat = meats[realIndex]
            end
          end
          if not meat then return end
          local typestr = Core.GetPartTypeName(partType)
          if not typestr then return end
          local row = {
            Meat = meat,
            Part = typestr,
          }
          if scarPointsMap[index] then
            local meat = scarPointsMap[index]
            row.ScarMeat = meat
          end

          table.insert(my_table.Rows, row)

          if part._MeatGuidBreak then
            local bI = GetMeatFunc:call(params, part._MeatGuidBreak)
            if not NullableInt32_HasValue:get_data(bI) then return end
            local breakIndex = NullableInt32_Value:get_data(bI)
            local breakMeat = meats[breakIndex]
            if meat then
              table.insert(my_table.Rows, {
                Meat = breakMeat,
                Breakable = true
              })
            end
          end
        end)
        table.insert(tables, my_table)
      end)
    end
  end
end

local function Clear()
  tables = {}
end

local forceShow = customConf.UseHotkey
Core.OnQuestStartPlaying(function ()
  Clear()
  LoadEm()
  enabled = true
  forceShow = customConf.UseHotkey
end)
Core.OnQuestStopPlaying(function ()
  Clear()
  enabled = false
  forceShow = false
end)

local function colorfulText(attr, meat, scarMeat, key)
  local isPhysics = attr == "Slash" or attr == "Blow" or attr == "Shot"
  local softValue = 24.9
  if isPhysics then
    softValue = 44.9
  end
  local value = meat[key]
  imgui.table_next_column()
  if value > softValue*1.2 then
    imgui.text_colored(tostring(value), 0xFF01308c)
  elseif value > softValue then
    imgui.text_colored(tostring(value), 0xFF00FFFF)
  elseif (value < 11) then
    imgui.text_colored(tostring(value), 0xFF666666)
  else
    imgui.text(tostring(value))
  end
  if scarMeat then
    local value = scarMeat[key]
    local displayValue = "(" .. value .. ")"
    imgui.same_line()
    if value > softValue*1.5 then
      imgui.text_colored(displayValue, 0xFF670587)
    return end
    if value > softValue then
      imgui.text_colored(displayValue, 0x96178517)
    return end
    if (value < 11) then
      imgui.text_colored(displayValue, 0xFF666666)
    return end
    imgui.text(displayValue)
  end
end
-- enabled = true
-- LoadEm()
-- log.debug("INIT")

local function meatValue (meat, scarMeat, key)
  if not scarMeat then
    return meat[key]
  end
  if scarMeat[key] then
    return meat[key] .. "(" .. scarMeat[key] .. ")"
  end
  return meat[key]
end

local hotkeyPressed = false
re.on_frame(function()
  scriptRunTime = scriptRunTime + 0.016
  if Core.IsLoading() then return end
  if not mod.Config.Enabled then return end
  if not enabled then return end
  if not #tables then return end

  if customConf.UseHotkey and customConf.Hotkey then
    local keyDown = reframework:is_key_down(customConf.Hotkey.key)
    local ctrl = reframework:is_key_down(0x11) or not customConf.Hotkey.ctrl
    local alt = reframework:is_key_down(0x12) or not customConf.Hotkey.alt
    local shift = reframework:is_key_down(0x10) or not customConf.Hotkey.shift
    local pressed = keyDown and ctrl and alt and shift
    if pressed and not (pressed == hotkeyPressed) then
      forceShow = not forceShow
      if forceShow then
        -- reset the autohide timer when the hotkey forces the table visible
        lastLoadTime = scriptRunTime
      end
    end
    hotkeyPressed = pressed
  end

  -- Auto-hide: if timeout reached, mark UI as hidden (forceShow = false)
  if customConf.AutoHide then
    if scriptRunTime - lastLoadTime > customConf.HideAfter then
      forceShow = false
      return
    end
  end

  -- if using hotkey and the UI is not forced visible, skip drawing (hotkey press will toggle)
  if customConf.UseHotkey and not forceShow then return end

  local fontSize = customConf.FontSize
  if not fontSize then
    fontSize = 18
  end
  -- local cjkFont = FontUtils.LoadImguiCJKFont(fontSize)
  local cjkFont = nil
  if customConf.UseRefFont then
    cjkFont = imgui.load_font(nil, fontSize)
  else
    cjkFont = FontUtils.LoadImguiCJKFont(fontSize)
  end
  local pushedFont = false
  if cjkFont then
    imgui.push_font(cjkFont)
    pushedFont = true
  end

  if not imgui.begin_window(CommonText.TableName, true, 4096 + 64) then
    mod.Config.Enabled = false
    if pushedFont then imgui.pop_font() end
    imgui.end_window()
    return
  end

  for i, table in ipairs(tables) do
    if imgui.begin_table("Hitzones", 10, 1 << 21, 25) then
      imgui.table_setup_column(table.Title, 1 << 3, 100)
      imgui.table_setup_column("Slash", 1 << 3, 55)
      imgui.table_setup_column("Blow", 1 << 3, 55)
      imgui.table_setup_column("Shot", 1 << 3, 55)
      imgui.table_setup_column("Fire", 1 << 3, 55)
      imgui.table_setup_column("Water", 1 << 3, 55)
      imgui.table_setup_column("Thunder", 1 << 3, 55)
      imgui.table_setup_column("Ice", 1 << 3, 55)
      imgui.table_setup_column("Dragon", 1 << 3, 55)
      -- imgui.table_setup_column("Stun", 1 << 3, 55)
      -- imgui.table_setup_column("LightPlant", 1 << 3, 55)
      imgui.table_headers_row()

      for index, row in ipairs(table.Rows) do
        local meat = row.Meat
        local part = row.Part
        local isBreakable = row.Breakable
        local scarMeat = row.ScarMeat
        imgui.table_next_row()
        imgui.table_next_column()
        if isBreakable then
          imgui.text_colored("↳ Before Break", 0xFF01308c)
        else
          imgui.text(part)
        end
        colorfulText("Slash", meat, scarMeat, "_Slash")
        colorfulText("Blow", meat, scarMeat, "_Blow")
        colorfulText("Shot", meat, scarMeat, "_Shot")
        colorfulText("Fire", meat, scarMeat, "_Fire")
        colorfulText("Water", meat, scarMeat, "_Water")
        colorfulText("Thunder", meat, scarMeat, "_Thunder")
        colorfulText("Ice", meat, scarMeat, "_Ice")
        colorfulText("Dragon", meat, scarMeat, "_Dragon")
      end

      imgui.end_table()
    end
  end

  if pushedFont then imgui.pop_font() end
  imgui.end_window()
end)
