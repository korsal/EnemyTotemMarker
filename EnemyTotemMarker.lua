local ADDON_NAME = ...

------------------------------------------------------------
-- Config
------------------------------------------------------------
local MARKER_SIZE = 32
local IMPORTANT_SCALE = 1.5 -- size multiplier for important PvP totems
local MARKER_Y_OFFSET = 6
local UPDATE_THROTTLE = 0.1
local GENERIC_TOTEM_ICON = "Interface\\Icons\\spell_nature_manaregentotem"

-- Important PvP totems (by spell id) get an enlarged icon. Edit freely.
local IMPORTANT_PVP = {
    [108269] = true, -- Capacitor Totem
    [8177]   = true, -- Grounding Totem
    [8143]   = true, -- Tremor Totem
    [2484]   = true, -- Earthbind Totem
    [51485]  = true, -- Earthgrab Totem
    [98008]  = true, -- Spirit Link Totem
    [108280] = true, -- Healing Tide Totem
    [5394]   = true, -- Healing Stream Totem
    [16190]  = true, -- Mana Tide Totem
    [120668] = true, -- Stormlash Totem
    [114051] = true, -- Windwalk Totem
}

-- Known totems: spellID -> lifetime (seconds).
-- ALL enemy totems get marked; totems listed here show their real icon AND a
-- countdown (resolved from GetSpellInfo at login, so icon/name are locale-safe).
-- Enemy totems expose no remaining-time API, so the timer counts down from this
-- value starting when the totem is first seen. Tweak durations as needed.
local TOTEM_DB = {
    [108269] = 5,   -- Capacitor Totem (stun)
    [8177]   = 45,  -- Grounding Totem (spell redirect)
    [8143]   = 6,   -- Tremor Totem (fear/sleep/charm break)
    [2484]   = 45,  -- Earthbind Totem (slow)
    [51485]  = 20,  -- Earthgrab Totem (root)
    [98008]  = 6,   -- Spirit Link Totem (damage redistribution)
    [108280] = 10,  -- Healing Tide Totem (raid heal)
    [5394]   = 15,  -- Healing Stream Totem
    [16190]  = 16,  -- Mana Tide Totem
    [120668] = 10,  -- Stormlash Totem (burst)
    [114051] = 6,   -- Windwalk Totem (snare removal)
    [2894]   = 60,  -- Fire Elemental Totem
    [2062]   = 60,  -- Earth Elemental Totem
    [3599]   = 60,  -- Searing Totem
}

-- Localized creature type string for "Totem".
local TOTEM_TYPE_BY_LOCALE = {
    enUS = "Totem", enGB = "Totem",
    ruRU = "Тотем",
    deDE = "Totem",
    frFR = "Totem",
    esES = "Tótem", esMX = "Tótem",
    ptBR = "Totem", ptPT = "Totem",
    itIT = "Totem",
    koKR = "토템",
    zhCN = "图腾", zhTW = "圖騰",
}
local TOTEM_TYPE = TOTEM_TYPE_BY_LOCALE[GetLocale()] or "Totem"

------------------------------------------------------------
-- State
------------------------------------------------------------
local activeMarkers = {}   -- unit token -> marker frame
local markerPool = {}      -- recycled marker frames
local iconByName = {}      -- localized totem name -> icon texture
local durByName = {}       -- localized totem name -> lifetime seconds
local importantByName = {} -- localized totem name -> true if important PvP totem
local startByGUID = {}     -- totem GUID -> first-seen GetTime()

------------------------------------------------------------
-- Totem database (resolved at login)
------------------------------------------------------------
local function BuildTotemDB()
    wipe(iconByName)
    wipe(durByName)
    wipe(importantByName)
    for spellID, duration in pairs(TOTEM_DB) do
        local name, _, icon = GetSpellInfo(spellID)
        if name and icon then
            iconByName[name] = icon
            durByName[name] = duration
            if IMPORTANT_PVP[spellID] then
                importantByName[name] = true
            end
        end
    end
end

------------------------------------------------------------
-- Marker pool
------------------------------------------------------------
local function MarkerOnUpdate(self, elapsed)
    self.throttle = (self.throttle or 0) - elapsed
    if self.throttle > 0 then return end
    self.throttle = UPDATE_THROTTLE

    local remain = self.duration - (GetTime() - self.startTime)
    if remain <= 0 then
        self.timer:SetText("")
        self:SetScript("OnUpdate", nil)
        if self.guid then startByGUID[self.guid] = nil end
        return
    end
    if remain < 10 then
        self.timer:SetFormattedText("%.1f", remain)
    else
        self.timer:SetFormattedText("%d", remain)
    end
end

local function AcquireMarker()
    local marker = tremove(markerPool)
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetSize(MARKER_SIZE, MARKER_SIZE)
        marker:SetFrameStrata("HIGH")

        local border = marker:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
        if border.SetColorTexture then
            border:SetColorTexture(0, 0, 0, 1)
        else
            border:SetTexture(0, 0, 0, 1)
        end
        marker.border = border

        local icon = marker:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim default icon border
        marker.icon = icon

        local cd = CreateFrame("Cooldown", nil, marker, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd.noCooldownCount = true -- tell OmniCC & co. to skip this one
        if cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(true) -- hide Blizzard's built-in number
        end
        marker.cd = cd

        local timer = marker:CreateFontString(nil, "OVERLAY")
        timer:SetPoint("CENTER", marker, "CENTER", 0, 0)
        timer:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
        timer:SetTextColor(1, 1, 0)
        marker.timer = timer
    end
    return marker
end

local function ReleaseMarker(marker)
    marker:SetScript("OnUpdate", nil)
    marker.timer:SetText("")
    marker.cd:SetCooldown(0, 0)
    marker:Hide()
    marker:ClearAllPoints()
    marker:SetParent(UIParent)
    tinsert(markerPool, marker)
end

------------------------------------------------------------
-- Unit checks
------------------------------------------------------------
-- Returns name if the unit is an attackable enemy totem, else nil.
local function GetTotemName(unit)
    if not UnitExists(unit) then return nil end
    if UnitCreatureType(unit) ~= TOTEM_TYPE then return nil end
    if not UnitCanAttack("player", unit) then return nil end
    return UnitName(unit)
end

------------------------------------------------------------
-- Marker management
------------------------------------------------------------
local function ShowMarkerForUnit(unit)
    local name = GetTotemName(unit)
    if not name then return end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end

    local marker = activeMarkers[unit] or AcquireMarker()
    activeMarkers[unit] = marker

    local size = importantByName[name] and (MARKER_SIZE * IMPORTANT_SCALE) or MARKER_SIZE
    marker:SetSize(size, size)
    marker.icon:SetTexture(iconByName[name] or GENERIC_TOTEM_ICON)
    marker:SetParent(nameplate)
    marker:ClearAllPoints()
    marker:SetPoint("BOTTOM", nameplate, "TOP", 0, MARKER_Y_OFFSET)

    -- Countdown (only for totems with a known lifetime).
    local duration = durByName[name]
    local guid = UnitGUID(unit)
    if duration then
        if guid and not startByGUID[guid] then
            startByGUID[guid] = GetTime()
        end
        local startTime = (guid and startByGUID[guid]) or GetTime()
        marker.guid = guid
        marker.startTime = startTime
        marker.duration = duration
        marker.throttle = 0
        marker.cd:SetCooldown(startTime, duration)
        marker:SetScript("OnUpdate", MarkerOnUpdate)
    else
        marker.guid = nil
        marker:SetScript("OnUpdate", nil)
        marker.timer:SetText("")
        marker.cd:SetCooldown(0, 0)
    end

    marker:Show()
end

local function HideMarkerForUnit(unit)
    local marker = activeMarkers[unit]
    if marker then
        ReleaseMarker(marker)
        activeMarkers[unit] = nil
    end
end

local function RefreshAll()
    for unit in pairs(activeMarkers) do
        HideMarkerForUnit(unit)
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
            or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            ShowMarkerForUnit(unit)
        end
    end
end

------------------------------------------------------------
-- Debug: /tm on a target prints its totem info for tuning the DB
------------------------------------------------------------
SLASH_TOTEMMARKER1 = "/tm"
SlashCmdList.TOTEMMARKER = function()
    local unit = "target"
    if not UnitExists(unit) then
        print("|cff33ff99EnemyTotemMarker|r: no target.")
        return
    end
    local guid = UnitGUID(unit)
    local npcID = guid and select(6, strsplit("-", guid))
    local name = UnitName(unit)
    print(("|cff33ff99EnemyTotemMarker|r: name=%q type=%q npcID=%s canAttack=%s icon=%s dur=%s")
        :format(
            tostring(name),
            tostring(UnitCreatureType(unit)),
            tostring(npcID),
            tostring(UnitCanAttack("player", unit)),
            tostring(name and iconByName[name] ~= nil),
            tostring(name and durByName[name] or "n/a")
        ))
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
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
        BuildTotemDB()
        pcall(SetCVar, "nameplateShowEnemyTotems", 1)
        print("|cff33ff99EnemyTotemMarker|r loaded. /tm to inspect a target.")
    end
end)
