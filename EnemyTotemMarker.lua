local ADDON_NAME = ...

------------------------------------------------------------
-- Config
------------------------------------------------------------
local MARKER_SIZE = 32
local DEFAULT_SCALE = 1.0   -- icon scale for a newly added / unconfigured totem
local IMPORTANT_SCALE = 1.5 -- seed scale for important PvP totems
local SCALE_MIN, SCALE_MAX = 0.5, 3.0
local MARKER_Y_OFFSET = 6
local UPDATE_THROTTLE = 0.1
local GENERIC_TOTEM_ICON = "Interface\\Icons\\spell_nature_manaregentotem"
local BORDER_SIZE_MAX = 6
local FONT_SIZE_MIN, FONT_SIZE_MAX = 6, 30

-- SavedVariables defaults.
local DEFAULTS = {
    borderSize = 2,  -- border thickness in pixels
    fontSize = 15,   -- countdown timer font size (all totems)
}

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
    [108273] = true, -- Windwalk Totem
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
    [108273] = 6,   -- Windwalk Totem (snare removal)
    [2894]   = 60,  -- Fire Elemental Totem
    [2062]   = 60,  -- Earth Elemental Totem
    [3599]   = 60,  -- Searing Totem
    [8190]   = 60,  -- Magma Totem (fire pulse AoE)
}

-- Totem element (school) -> border color. Edit freely.
local ELEMENT_COLOR = {
    Fire  = { 1.00, 0.25, 0.10 }, -- orange-red
    Earth = { 0.60, 0.40, 0.15 }, -- brown
    Water = { 0.15, 0.55, 1.00 }, -- blue
    Air   = { 0.70, 0.95, 1.00 }, -- pale cyan
}
local DEFAULT_BORDER_COLOR = { 0, 0, 0 } -- unknown / non-DB totems

-- spellID -> element, used to tint each totem's border.
local TOTEM_ELEMENT = {
    [108269] = "Air",   -- Capacitor Totem
    [8177]   = "Air",   -- Grounding Totem
    [8143]   = "Earth", -- Tremor Totem
    [2484]   = "Earth", -- Earthbind Totem
    [51485]  = "Earth", -- Earthgrab Totem
    [98008]  = "Air",   -- Spirit Link Totem
    [108280] = "Water", -- Healing Tide Totem
    [5394]   = "Water", -- Healing Stream Totem
    [16190]  = "Water", -- Mana Tide Totem
    [120668] = "Air",   -- Stormlash Totem
    [108273] = "Air",   -- Windwalk Totem
    [2894]   = "Fire",  -- Fire Elemental Totem
    [2062]   = "Earth", -- Earth Elemental Totem
    [3599]   = "Fire",  -- Searing Totem
    [8190]   = "Fire",  -- Magma Totem
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
local scaleByName = {}     -- localized totem name -> icon scale multiplier
local colorByName = {}     -- localized totem name -> element border color
local startByGUID = {}     -- totem GUID -> first-seen GetTime()
local db                   -- SavedVariables (EnemyTotemMarkerDB), set at login

------------------------------------------------------------
-- Totem database (resolved from the tracked list at login / on edit)
------------------------------------------------------------
-- Builds the localized-name lookups from db.spells (the user's tracked
-- list). Built-in TOTEM_DB / TOTEM_ELEMENT supply default lifetime and
-- element for known spell ids; per-totem scale comes from the saved list.
local function BuildTotemDB()
    wipe(iconByName)
    wipe(durByName)
    wipe(scaleByName)
    wipe(colorByName)
    if not (db and db.spells) then return end

    for spellID, cfg in pairs(db.spells) do
        local name, _, icon = GetSpellInfo(spellID)
        if name then
            if icon then iconByName[name] = icon end
            durByName[name] = TOTEM_DB[spellID]          -- built-in lifetime, if known
            scaleByName[name] = cfg.scale or DEFAULT_SCALE
            local element = TOTEM_ELEMENT[spellID]
            if element then
                colorByName[name] = ELEMENT_COLOR[element]
            end
        end
    end
end

------------------------------------------------------------
-- Marker pool
------------------------------------------------------------
local function SetSolidColor(tex, r, g, b, a)
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture(r, g, b, a)
    end
end

-- (Re)anchor a marker's border to the configured thickness.
local function ApplyBorder(marker)
    local t = (db and db.borderSize) or DEFAULTS.borderSize
    marker.border:ClearAllPoints()
    marker.border:SetPoint("TOPLEFT", -t, t)
    marker.border:SetPoint("BOTTOMRIGHT", t, -t)
    marker.border:SetShown(t > 0)
end

-- Re-apply border thickness to all live and pooled markers.
local function RefreshBorders()
    for _, marker in pairs(activeMarkers) do
        ApplyBorder(marker)
    end
    for _, marker in ipairs(markerPool) do
        ApplyBorder(marker)
    end
end

-- Apply the timer font, scaled by the marker's per-totem icon scale so the
-- countdown grows/shrinks together with the icon.
local function ApplyFont(marker)
    local size = ((db and db.fontSize) or DEFAULTS.fontSize) * (marker.totemScale or 1)
    size = floor(size + 0.5)
    if size < 1 then size = 1 end
    marker.timer:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
end

-- Re-apply timer font size to all live and pooled markers.
local function RefreshFonts()
    for _, marker in pairs(activeMarkers) do
        ApplyFont(marker)
    end
    for _, marker in ipairs(markerPool) do
        ApplyFont(marker)
    end
end

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
        SetSolidColor(border, 0, 0, 0, 1)
        marker.border = border
        ApplyBorder(marker)

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
        timer:SetTextColor(1, 1, 0)
        marker.timer = timer
        ApplyFont(marker)
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

    local scl = scaleByName[name] or DEFAULT_SCALE
    marker:SetSize(MARKER_SIZE * scl, MARKER_SIZE * scl)
    marker.totemScale = scl
    ApplyFont(marker)
    marker.icon:SetTexture(iconByName[name] or GENERIC_TOTEM_ICON)

    local color = colorByName[name] or DEFAULT_BORDER_COLOR
    SetSolidColor(marker.border, color[1], color[2], color[3], 1)

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
-- Tracked totem list management
------------------------------------------------------------
-- Snapshot of db.spells as a name-sorted array of {id, name, icon}.
local function GetSortedSpellList()
    local list = {}
    if db and db.spells then
        for spellID in pairs(db.spells) do
            local name, _, icon = GetSpellInfo(spellID)
            list[#list + 1] = {
                id = spellID,
                name = name or ("Spell " .. spellID),
                icon = icon or GENERIC_TOTEM_ICON,
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Returns ok, idOrErr, name. On success: true, spellID, name.
local function AddSpellByID(input)
    local id = tonumber(input and input:match("%d+"))
    if not id then return false, "enter a numeric spell ID" end
    local name = GetSpellInfo(id)
    if not name then return false, "unknown spell ID: " .. id end
    if not db.spells[id] then
        db.spells[id] = { scale = DEFAULT_SCALE }
    end
    BuildTotemDB()
    RefreshAll()
    return true, id, name
end

local function RemoveSpellByID(id)
    if id and db.spells and db.spells[id] then
        db.spells[id] = nil
        BuildTotemDB()
        RefreshAll()
        return true
    end
    return false
end

local function SetSpellScale(id, scale)
    if id and db.spells and db.spells[id] then
        db.spells[id].scale = scale
        BuildTotemDB()
        RefreshAll()
    end
end

------------------------------------------------------------
-- Options panel (ESC -> Options -> AddOns)
------------------------------------------------------------
local optionsCategory
local function SetupOptions()
    if optionsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local NUM_ROWS, ROW_HEIGHT = 16, 22
    local selectedID
    local UpdateList, UpdateDetail, UpdatePreview   -- forward declarations
    local settingScale = false       -- guards programmatic slider updates

    -- Small left/right arrow stepper button (restores the +/- arrows).
    local function MakeStepper(parent, isLeft, onClick)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(18, 18)
        local base = isLeft and "PrevPage" or "NextPage"
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. base .. "-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. base .. "-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. base .. "-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", onClick)
        return b
    end

    local panel = CreateFrame("Frame")
    panel.name = "EnemyTotemMarker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("EnemyTotemMarker — tracked totems")

    -- Global border thickness slider (very top), with +/- arrow steppers.
    local borderSlider = CreateFrame("Slider", "ETMBorderSlider", panel, "OptionsSliderTemplate")
    borderSlider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 24, -30)
    borderSlider:SetMinMaxValues(0, BORDER_SIZE_MAX)
    borderSlider:SetValueStep(1)
    borderSlider:SetObeyStepOnDrag(true)
    borderSlider:SetWidth(180)
    ETMBorderSliderLow:SetText("0")
    ETMBorderSliderHigh:SetText(tostring(BORDER_SIZE_MAX))
    borderSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        ETMBorderSliderText:SetText("Border thickness: " .. value)
        if db then
            db.borderSize = value
            RefreshBorders()
            if UpdatePreview then UpdatePreview() end
        end
    end)
    MakeStepper(borderSlider, true, function()
        borderSlider:SetValue(max(0, min(BORDER_SIZE_MAX,
            (db and db.borderSize or DEFAULTS.borderSize) - 1)))
    end):SetPoint("RIGHT", borderSlider, "LEFT", -4, 0)
    MakeStepper(borderSlider, false, function()
        borderSlider:SetValue(max(0, min(BORDER_SIZE_MAX,
            (db and db.borderSize or DEFAULTS.borderSize) + 1)))
    end):SetPoint("LEFT", borderSlider, "RIGHT", 4, 0)

    -- Global timer font size slider (all totems), with +/- arrow steppers.
    local fontSlider = CreateFrame("Slider", "ETMFontSlider", panel, "OptionsSliderTemplate")
    fontSlider:SetPoint("TOPLEFT", borderSlider, "BOTTOMLEFT", 0, -40)
    fontSlider:SetMinMaxValues(FONT_SIZE_MIN, FONT_SIZE_MAX)
    fontSlider:SetValueStep(1)
    fontSlider:SetObeyStepOnDrag(true)
    fontSlider:SetWidth(180)
    ETMFontSliderLow:SetText(tostring(FONT_SIZE_MIN))
    ETMFontSliderHigh:SetText(tostring(FONT_SIZE_MAX))
    fontSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value + 0.5)
        ETMFontSliderText:SetText("Timer font size: " .. value)
        if db then
            db.fontSize = value
            RefreshFonts()
            if UpdatePreview then UpdatePreview() end
        end
    end)
    MakeStepper(fontSlider, true, function()
        fontSlider:SetValue(max(FONT_SIZE_MIN, min(FONT_SIZE_MAX,
            (db and db.fontSize or DEFAULTS.fontSize) - 1)))
    end):SetPoint("RIGHT", fontSlider, "LEFT", -4, 0)
    MakeStepper(fontSlider, false, function()
        fontSlider:SetValue(max(FONT_SIZE_MIN, min(FONT_SIZE_MAX,
            (db and db.fontSize or DEFAULTS.fontSize) + 1)))
    end):SetPoint("LEFT", fontSlider, "RIGHT", 4, 0)

    -- Add-by-spell-ID controls (below the global sliders).
    local addLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", -24, -28)
    addLabel:SetText("Add totem by spell ID:")

    local addBox = CreateFrame("EditBox", "ETMAddBox", panel, "InputBoxTemplate")
    addBox:SetSize(110, 20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(56, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")

    -- Scrolling list of tracked totems.
    local scroll = CreateFrame("ScrollFrame", "ETMSpellScroll", panel, "FauxScrollFrameTemplate")
    scroll:SetSize(220, NUM_ROWS * ROW_HEIGHT)
    scroll:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -16)

    -- Rows are children of the panel (not the scroll frame) and anchored to
    -- it; FauxScrollFrame only manages the scrollbar + offset.
    local rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(204, ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.25, 0.5, 1, 0.25)
        sel:Hide()
        row.sel = sel

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = icon

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        row:SetScript("OnClick", function(self)
            selectedID = self.id
            UpdateList()
            UpdateDetail()
        end)
        rows[i] = row
    end

    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateList)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local sb = ETMSpellScrollScrollBar
        if sb then sb:SetValue(sb:GetValue() - delta * ROW_HEIGHT) end
    end)

    -- Detail pane for the selected totem (right side).
    local detail = CreateFrame("Frame", nil, panel)
    detail:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 48, 0)
    detail:SetSize(260, NUM_ROWS * ROW_HEIGHT)

    -- Preview icon sits in a fixed slot and is decorated to match the marker
    -- (element-colored border + per-totem scale). Text/slider use fixed
    -- anchors so the icon resizing never shoves them around.
    local dBorder = detail:CreateTexture(nil, "BACKGROUND")

    local dIcon = detail:CreateTexture(nil, "ARTWORK")
    dIcon:SetSize(36, 36)
    dIcon:SetPoint("CENTER", detail, "TOPLEFT", 46, -46)
    dIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Sample countdown number on the preview, mirrors the marker timer font.
    local dTimer = detail:CreateFontString(nil, "OVERLAY")
    dTimer:SetPoint("CENTER", dIcon, "CENTER", 0, 0)
    dTimer:SetTextColor(1, 1, 0)

    local dName = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    dName:SetPoint("TOPLEFT", detail, "TOPLEFT", 100, -10)
    dName:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
    dName:SetJustifyH("LEFT")

    local dID = detail:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dID:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -6)

    local scaleSlider = CreateFrame("Slider", "ETMScaleSlider", detail, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", detail, "TOPLEFT", 30, -118)
    scaleSlider:SetMinMaxValues(SCALE_MIN, SCALE_MAX)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetWidth(200)
    ETMScaleSliderLow:SetText(tostring(SCALE_MIN))
    ETMScaleSliderHigh:SetText(tostring(SCALE_MAX))
    ETMScaleSliderText:SetText("Icon scale")
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = floor(value * 20 + 0.5) / 20 -- snap to 0.05
        ETMScaleSliderText:SetText(("Icon scale: %.2f"):format(value))
        if settingScale then return end
        SetSpellScale(selectedID, value)
        UpdatePreview()
    end)
    MakeStepper(scaleSlider, true, function()
        if selectedID and db.spells and db.spells[selectedID] then
            scaleSlider:SetValue(max(SCALE_MIN, min(SCALE_MAX,
                (db.spells[selectedID].scale or DEFAULT_SCALE) - 0.05)))
        end
    end):SetPoint("RIGHT", scaleSlider, "LEFT", -4, 0)
    MakeStepper(scaleSlider, false, function()
        if selectedID and db.spells and db.spells[selectedID] then
            scaleSlider:SetValue(max(SCALE_MIN, min(SCALE_MAX,
                (db.spells[selectedID].scale or DEFAULT_SCALE) + 0.05)))
        end
    end):SetPoint("LEFT", scaleSlider, "RIGHT", 4, 0)

    local removeBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    removeBtn:SetSize(120, 24)
    removeBtn:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -4, -28)
    removeBtn:SetText("Remove totem")
    removeBtn:SetScript("OnClick", function()
        if RemoveSpellByID(selectedID) then
            selectedID = nil
            UpdateList()
            UpdateDetail()
        end
    end)

    -- Decorate the preview icon to match the on-nameplate marker: per-totem
    -- scale + element-colored border at the configured thickness.
    local PREVIEW_BASE = 28
    function UpdatePreview()
        if not (selectedID and db.spells and db.spells[selectedID]) then return end
        local scl = db.spells[selectedID].scale or DEFAULT_SCALE
        local sz = PREVIEW_BASE * scl
        dIcon:SetSize(sz, sz)

        local t = (db and db.borderSize) or DEFAULTS.borderSize
        dBorder:ClearAllPoints()
        dBorder:SetPoint("TOPLEFT", dIcon, "TOPLEFT", -t, t)
        dBorder:SetPoint("BOTTOMRIGHT", dIcon, "BOTTOMRIGHT", t, -t)
        dBorder:SetShown(t > 0)
        local element = TOTEM_ELEMENT[selectedID]
        local c = (element and ELEMENT_COLOR[element]) or DEFAULT_BORDER_COLOR
        SetSolidColor(dBorder, c[1], c[2], c[3], 1)

        -- Sample timer scaled by the totem scale, matching the marker's
        -- font-to-icon ratio (preview icon base differs from MARKER_SIZE).
        local fsize = floor(((db and db.fontSize or DEFAULTS.fontSize)
            * scl * PREVIEW_BASE / MARKER_SIZE) + 0.5)
        if fsize < 1 then fsize = 1 end
        dTimer:SetFont(STANDARD_TEXT_FONT, fsize, "OUTLINE")
        dTimer:SetText(tostring(TOTEM_DB[selectedID] or 10))
    end

    function UpdateDetail()
        if not (selectedID and db.spells and db.spells[selectedID]) then
            detail:Hide()
            return
        end
        detail:Show()
        local name, _, icon = GetSpellInfo(selectedID)
        dIcon:SetTexture(icon or GENERIC_TOTEM_ICON)
        dName:SetText(name or ("Spell " .. selectedID))
        dID:SetText("Spell ID: " .. selectedID)
        settingScale = true
        scaleSlider:SetValue(db.spells[selectedID].scale or DEFAULT_SCALE)
        settingScale = false
        UpdatePreview()
    end

    function UpdateList()
        local list = GetSortedSpellList()
        local offset = FauxScrollFrame_GetOffset(scroll)
        FauxScrollFrame_Update(scroll, #list, NUM_ROWS, ROW_HEIGHT)
        for i = 1, NUM_ROWS do
            local row = rows[i]
            local data = list[i + offset]
            if data then
                row.id = data.id
                row.icon:SetTexture(data.icon)
                row.text:SetText(data.name)
                row.sel:SetShown(data.id == selectedID)
                row:Show()
            else
                row.id = nil
                row:Hide()
            end
        end
    end

    addBtn:SetScript("OnClick", function()
        local ok, idOrErr, name = AddSpellByID(addBox:GetText())
        if ok then
            addBox:SetText("")
            addBox:ClearFocus()
            selectedID = idOrErr
            UpdateList()
            UpdateDetail()
            print(("|cff33ff99EnemyTotemMarker|r: added %s (%d)."):format(name, idOrErr))
        else
            print("|cff33ff99EnemyTotemMarker|r: " .. tostring(idOrErr))
        end
    end)
    addBox:SetScript("OnEnterPressed", function() addBtn:Click() end)

    panel:SetScript("OnShow", function()
        if db then
            borderSlider:SetValue(db.borderSize or DEFAULTS.borderSize)
            fontSlider:SetValue(db.fontSize or DEFAULTS.fontSize)
        end
        if not (selectedID and db and db.spells and db.spells[selectedID]) then
            local list = GetSortedSpellList()
            selectedID = list[1] and list[1].id or nil
        end
        UpdateList()
        UpdateDetail()
    end)

    optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, "EnemyTotemMarker")
    Settings.RegisterAddOnCategory(optionsCategory)
end

local function OpenOptions()
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
    else
        print("|cff33ff99EnemyTotemMarker|r: options panel unavailable.")
    end
end

------------------------------------------------------------
-- Debug: /tm on a target prints its totem info for tuning the DB
-- /tm config opens the options panel
------------------------------------------------------------
SLASH_TOTEMMARKER1 = "/tm"
SlashCmdList.TOTEMMARKER = function(msg)
    if msg and msg:lower():match("^%s*config") then
        OpenOptions()
        return
    end
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
        EnemyTotemMarkerDB = EnemyTotemMarkerDB or {}
        db = EnemyTotemMarkerDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        -- Seed the tracked-totem list once from the built-in DB; afterwards
        -- it is fully user-managed (add/remove via the options panel).
        if not db.spells then
            db.spells = {}
            for spellID in pairs(TOTEM_DB) do
                db.spells[spellID] = {
                    scale = IMPORTANT_PVP[spellID] and IMPORTANT_SCALE or DEFAULT_SCALE,
                }
            end
        end
        BuildTotemDB()
        pcall(SetupOptions)
        RefreshBorders()
        RefreshFonts()
        pcall(SetCVar, "nameplateShowEnemyTotems", 1)
        print("|cff33ff99EnemyTotemMarker|r loaded. /tm to inspect a target, /tm config for options.")
    end
end)
