local ADDON_NAME = ...

local MARKER_SIZE     = 32
local DEFAULT_SCALE   = 1.0
local IMPORTANT_SCALE = 1.5
local MARKER_Y_OFFSET = 6
local UPDATE_THROTTLE = 0.05
local BORDER_SIZE_MAX = 6
local FONT_SIZE_MIN   = 6
local FONT_SIZE_MAX   = 30
local TREMOR_TICK     = 3

local DEFAULTS = { borderSize = 2, fontSize = 15 }

local ELEMENT_COLOR = {
  Fire  = {1.00, 0.25, 0.10},
  Earth = {0.60, 0.40, 0.15},
  Water = {0.15, 0.55, 1.00},
  Air   = {0.70, 0.95, 1.00},
}
local COLOR_BLACK = {0, 0, 0}

-- timer modes:
--   nil / false = no timer shown
--   "lifetime"  = countdown of totem lifetime
--   "tremor"    = tremor tick countdown only (no lifetime)
local TOTEM_DATA = {
  -- AIR
  ["Grace of Air Totem"]      = {icon="Interface\\Icons\\Spell_Nature_Invisibilitytotem",      element="Air",   duration=120},
  ["Tranquil Air Totem"]      = {icon="Interface\\Icons\\Spell_Nature_Brilliant",              element="Air",   duration=120},
  ["Windwall Totem"]          = {icon="Interface\\Icons\\Spell_Nature_StoneClawTotem",         element="Air",   duration=120},
  ["Windfury Totem"]          = {icon="Interface\\Icons\\Spell_Nature_Windfury",               element="Air",   duration=120},
  ["Wrath of Air Totem"]      = {icon="Interface\\Icons\\Spell_Nature_Slowingtotem",           element="Air",   duration=120},
  ["Grounding Totem"]         = {icon="Interface\\Icons\\Spell_Nature_Groundingtotem",         element="Air",   duration=45,  important=true, timer="lifetime"},
  ["Nature Resistance Totem"] = {icon="Interface\\Icons\\Spell_Nature_NatureResistanceTotem",  element="Air",   duration=120},

  -- EARTH
  ["Tremor Totem"]            = {icon="Interface\\Icons\\Spell_Nature_Tremortotem",            element="Earth", duration=120, important=true, timer="tremor"},
  ["Earthbind Totem"]         = {icon="Interface\\Icons\\Spell_Nature_StrengthofEarthTotem02", element="Earth", duration=45,  important=true, timer="lifetime"},
  ["Stoneskin Totem"]         = {icon="Interface\\Icons\\Spell_Nature_StoneSkinTotem",         element="Earth", duration=120},
  ["Stoneclaw Totem"]         = {icon="Interface\\Icons\\Spell_Nature_StoneClawTotem",         element="Earth", duration=15},
  ["Strength of Earth Totem"] = {icon="Interface\\Icons\\Spell_Nature_EarthBindTotem",         element="Earth", duration=120},
  ["Earth Elemental Totem"]   = {icon="Interface\\Icons\\Spell_Nature_EarthElemental_Totem",   element="Earth", duration=120, important=true},
  ["Totem of Wrath"]          = {icon="Interface\\Icons\\Spell_Fire_TotemofWrath",             element="Fire",  duration=120},

  -- FIRE
  ["Searing Totem"]           = {icon="Interface\\Icons\\Spell_Fire_SearingTotem",             element="Fire",  duration=60},
  ["Fire Nova Totem"]         = {icon="Interface\\Icons\\Spell_Fire_SealOfFire",               element="Fire",  duration=5,   important=true, timer="lifetime"},
  ["Magma Totem"]             = {icon="Interface\\Icons\\Spell_Fire_SelfDestruct",             element="Fire",  duration=20,  important=true},
  ["Flametongue Totem"]       = {icon="Interface\\Icons\\Spell_Nature_GuardianWard",           element="Fire",  duration=120},
  ["Fire Elemental Totem"]    = {icon="Interface\\Icons\\Spell_Fire_ElementalDevastation",    element="Fire",  duration=120, important=true},
  ["Frost Resistance Totem"]  = {icon="Interface\\Icons\\Spell_FrostResistanceTotem_01",      element="Water", duration=120},

  -- WATER
  ["Healing Stream Totem"]    = {icon="Interface\\Icons\\INV_Spear_04",                        element="Water", duration=60,  important=true},
  ["Mana Spring Totem"]       = {icon="Interface\\Icons\\Spell_Nature_ManaRegentotem",        element="Water", duration=120},
  ["Mana Tide Totem"]         = {icon="Interface\\Icons\\Spell_Frost_SummonWaterElemental",    element="Water", duration=12,  important=true, timer="lifetime"},
  ["Disease Cleansing Totem"] = {icon="Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",  element="Water", duration=120},
  ["Poison Cleansing Totem"]  = {icon="Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",   element="Water", duration=120},
  ["Fire Resistance Totem"]   = {icon="Interface\\Icons\\Spell_FireResistanceTotem_01",        element="Water", duration=120},
  ["Cleansing Totem"]         = {icon="Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",  element="Water", duration=120},
}

local TOTEM_TYPE = ({
  enUS="Totem", enGB="Totem", ruRU="Тотем", deDE="Totem", frFR="Totem",
  esES="Tótem", esMX="Tótem", ptBR="Totem", ptPT="Totem", itIT="Totem",
  koKR="토템", zhCN="图腾", zhTW="圖騰",
})[GetLocale()] or "Totem"

local activeMarkers = {}
local markerPool    = {}
local startByGUID   = {}
local db

local function NormalizeName(name)
  if not name then return nil end
  return tostring(name):gsub("%s+[IVX]+$",""):gsub("%s*%b()",""):gsub("%s+$","")
end

local function GetData(name)
  if not name then return nil end
  return TOTEM_DATA[name] or TOTEM_DATA[NormalizeName(name) or ""]
end

local function SetSolidColor(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r,g,b,a) else tex:SetTexture(r,g,b,a) end
end

local function ApplyBorder(m)
  local t = (db and db.borderSize) or DEFAULTS.borderSize
  m.border:ClearAllPoints()
  m.border:SetPoint("TOPLEFT",    -t,  t)
  m.border:SetPoint("BOTTOMRIGHT", t, -t)
  m.border:SetShown(t > 0)
end

local function RefreshBorders()
  for _,m in pairs(activeMarkers) do ApplyBorder(m) end
  for _,m in ipairs(markerPool)   do ApplyBorder(m) end
end

local function ApplyFont(m)
  local sz = max(1, floor(((db and db.fontSize or DEFAULTS.fontSize) * (m.totemScale or 1)) + 0.5))
  m.timer:SetFont(STANDARD_TEXT_FONT, sz, "OUTLINE")
end

local function RefreshFonts()
  for _,m in pairs(activeMarkers) do ApplyFont(m) end
  for _,m in ipairs(markerPool)   do ApplyFont(m) end
end

local function MarkerOnUpdate(self, elapsed)
  self.throttle = (self.throttle or 0) - elapsed
  if self.throttle > 0 then return end
  self.throttle = UPDATE_THROTTLE

  local now    = GetTime()
  local remain = self.duration - (now - self.startTime)

  if remain <= 0 then
    self.timer:SetText("")
    self:SetScript("OnUpdate", nil)
    if self.guid then startByGUID[self.guid] = nil end
    return
  end

  local mode = self.timerMode
  if mode == "tremor" then
    -- only tick countdown, no lifetime
    local till = TREMOR_TICK - ((now - self.startTime) % TREMOR_TICK)
    self.timer:SetFormattedText("%.1f", till)
  elseif mode == "lifetime" then
    if remain < 10 then
      self.timer:SetFormattedText("%.1f", remain)
    else
      self.timer:SetFormattedText("%d", remain)
    end
  else
    self.timer:SetText("")
  end
end

local function AcquireMarker()
  local m = tremove(markerPool)
  if not m then
    m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(MARKER_SIZE, MARKER_SIZE)
    m:SetFrameStrata("HIGH")

    local border = m:CreateTexture(nil, "BACKGROUND")
    SetSolidColor(border, 0,0,0,1)
    m.border = border

    local icon = m:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    m.icon = icon

    local timer = m:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("CENTER", m, "CENTER", 0, 0)
    timer:SetTextColor(1, 1, 0)
    m.timer = timer

    ApplyBorder(m)
    ApplyFont(m)
  end
  return m
end

local function ReleaseMarker(m)
  m:SetScript("OnUpdate", nil)
  m.timer:SetText("")
  m.timerMode = nil
  m.guid      = nil
  m:Hide()
  m:ClearAllPoints()
  m:SetParent(UIParent)
  tinsert(markerPool, m)
end

local function IsEnemyTotem(unit)
  return UnitExists(unit)
    and UnitCreatureType(unit) == TOTEM_TYPE
    and UnitCanAttack("player", unit)
end

local function GetNamePlate(unit)
  if C_NamePlate and C_NamePlate.GetNamePlateForUnit then return C_NamePlate.GetNamePlateForUnit(unit) end
end

local function GetNamePlates()
  if C_NamePlate and C_NamePlate.GetNamePlates then return C_NamePlate.GetNamePlates() end
  return {}
end

local function ShowMarkerForUnit(unit)
  if not IsEnemyTotem(unit) then return end
  local nameplate = GetNamePlate(unit)
  if not nameplate then return end

  local rawName = UnitName(unit)
  local data    = GetData(rawName)

  local m = activeMarkers[unit] or AcquireMarker()
  activeMarkers[unit] = m

  local scl = (data and data.important) and IMPORTANT_SCALE or DEFAULT_SCALE
  m:SetSize(MARKER_SIZE * scl, MARKER_SIZE * scl)
  m.totemScale = scl
  ApplyFont(m)
  ApplyBorder(m)

  m.icon:SetTexture((data and data.icon) or "Interface\\Icons\\spell_nature_manaregentotem")

  local col = (data and data.element and ELEMENT_COLOR[data.element]) or COLOR_BLACK
  SetSolidColor(m.border, col[1], col[2], col[3], 1)

  m:SetParent(nameplate)
  m:ClearAllPoints()
  m:SetPoint("BOTTOM", nameplate, "TOP", 0, MARKER_Y_OFFSET)

  local timerMode = data and data.timer   -- "lifetime" / "tremor" / nil
  local duration  = data and data.duration
  local guid      = UnitGUID(unit)

  if duration and timerMode then
    if guid and not startByGUID[guid] then startByGUID[guid] = GetTime() end
    local st     = (guid and startByGUID[guid]) or GetTime()
    m.guid       = guid
    m.startTime  = st
    m.duration   = duration
    m.timerMode  = timerMode
    m.throttle   = 0
    m:SetScript("OnUpdate", MarkerOnUpdate)
  else
    m.guid      = nil
    m.timerMode = nil
    m:SetScript("OnUpdate", nil)
    m.timer:SetText("")
  end

  m:Show()
end

local function HideMarkerForUnit(unit)
  local m = activeMarkers[unit]
  if m then ReleaseMarker(m); activeMarkers[unit] = nil end
end

local function RefreshAll()
  for unit in pairs(activeMarkers) do HideMarkerForUnit(unit) end
  for _, plate in ipairs(GetNamePlates()) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then ShowMarkerForUnit(unit) end
  end
end

local optionsPanel
local function SetupOptions()
  if optionsPanel then return end
  local panel = CreateFrame("Frame", "EnemyTotemMarkerOptionsPanel")
  panel.name = "EnemyTotemMarker"

  local title = panel:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
  title:SetPoint("TOPLEFT",16,-16)
  title:SetText("EnemyTotemMarker — TBC 2.5.5")

  local sub = panel:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-8)
  sub:SetText("Timers: Earthbind / Grounding / ManaTide / FireNova lifetime  |  Tremor tick")

  local bLabel=panel:CreateFontString(nil,"ARTWORK","GameFontNormal")
  bLabel:SetPoint("TOPLEFT",sub,"BOTTOMLEFT",0,-24)
  local function UpdB() bLabel:SetText("Border thickness: "..(db and db.borderSize or DEFAULTS.borderSize)) end UpdB()
  local bM=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate") bM:SetSize(28,22) bM:SetPoint("TOPLEFT",bLabel,"BOTTOMLEFT",0,-6) bM:SetText("-")
  bM:SetScript("OnClick",function() db.borderSize=max(0,(db.borderSize or DEFAULTS.borderSize)-1) RefreshBorders() UpdB() end)
  local bP=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate") bP:SetSize(28,22) bP:SetPoint("LEFT",bM,"RIGHT",6,0) bP:SetText("+")
  bP:SetScript("OnClick",function() db.borderSize=min(BORDER_SIZE_MAX,(db.borderSize or DEFAULTS.borderSize)+1) RefreshBorders() UpdB() end)

  local fLabel=panel:CreateFontString(nil,"ARTWORK","GameFontNormal")
  fLabel:SetPoint("TOPLEFT",bM,"BOTTOMLEFT",0,-18)
  local function UpdF() fLabel:SetText("Timer font size: "..(db and db.fontSize or DEFAULTS.fontSize)) end UpdF()
  local fM=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate") fM:SetSize(28,22) fM:SetPoint("TOPLEFT",fLabel,"BOTTOMLEFT",0,-6) fM:SetText("-")
  fM:SetScript("OnClick",function() db.fontSize=max(FONT_SIZE_MIN,(db.fontSize or DEFAULTS.fontSize)-1) RefreshFonts() UpdF() end)
  local fP=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate") fP:SetSize(28,22) fP:SetPoint("LEFT",fM,"RIGHT",6,0) fP:SetText("+")
  fP:SetScript("OnClick",function() db.fontSize=min(FONT_SIZE_MAX,(db.fontSize or DEFAULTS.fontSize)+1) RefreshFonts() UpdF() end)

  InterfaceOptions_AddCategory(panel)
  optionsPanel = panel
end

local function OpenOptions()
  if optionsPanel then InterfaceOptionsFrame_OpenToCategory(optionsPanel) InterfaceOptionsFrame_OpenToCategory(optionsPanel) end
end

SLASH_TOTEMMARKER1 = "/tm"
SlashCmdList.TOTEMMARKER = function(msg)
  if msg and msg:lower():match("^%s*config") then OpenOptions() return end
  local unit = "target"
  if not UnitExists(unit) then print("|cff33ff99ETM|r: no target.") return end
  local name  = UnitName(unit)
  local data  = GetData(name)
  local guid  = UnitGUID(unit)
  local npcID = guid and select(6, strsplit("-", guid))
  print(("|cff33ff99ETM|r: name=%q norm=%q type=%q npcID=%s hasData=%s timer=%s"):format(
    tostring(name), tostring(NormalizeName(name)),
    tostring(UnitCreatureType(unit)), tostring(npcID),
    tostring(data~=nil), tostring(data and data.timer or "none")))
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "NAME_PLATE_UNIT_ADDED" then
    ShowMarkerForUnit(arg1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    HideMarkerForUnit(arg1)
  elseif event == "PLAYER_ENTERING_WORLD" then
    RefreshAll()
  elseif event == "PLAYER_LOGIN" then
    EnemyTotemMarkerDB = EnemyTotemMarkerDB or {}
    db = EnemyTotemMarkerDB
    for k,v in pairs(DEFAULTS) do if db[k]==nil then db[k]=v end end
    pcall(SetupOptions)
    RefreshBorders()
    RefreshFonts()
    pcall(SetCVar, "nameplateShowEnemyTotems", 1)
    print("|cff33ff99EnemyTotemMarker|r v7b TBC 2.5.5. /tm config  |  /tm — target info.")
  end
end)
