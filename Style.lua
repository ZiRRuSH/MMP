-- MaliStyleKit 3: the themeable flat UI shared by the Mali addons. Load first.
local addonName, ns = ...

local style = {}
ns.style = style

style.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
local FALLBACK_LOCALES = { koKR = true, zhCN = true, zhTW = true }
local FILE_NAMES = { regular = "Inter-Regular.ttf", medium = "Inter-Medium.ttf" }
local DANGER = { 0.92, 0.25, 0.25, 1 }
local DISABLED_EDGE = { 0.18, 0.17, 0.2, 0.75 }
local MIN_SCALE, MAX_SCALE, MAX_WINDOW_SCALE = 0.8, 1.4, 1.25

-- Theme data

local SOULSTONE = {
    background = { 13 / 255, 8 / 255, 18 / 255 },
    border = { 74 / 255, 42 / 255, 94 / 255 },
    accent = { 176 / 255, 108 / 255, 255 / 255 },
    highlight = { 108 / 255, 255 / 255, 154 / 255 },
    selection = { 58 / 255, 22 / 255, 80 / 255 },
    secondary = { 214 / 255, 176 / 255, 255 / 255 },
}
local MALI = {
    background = { 0.055, 0.055, 0.07 },
    border = { 0.3, 0.25, 0.4 },
    accent = { 242 / 255, 158 / 255, 59 / 255 },
    highlight = { 0.58, 0.47, 0.7 },
    selection = { 0.3, 0.2, 0.45 },
    secondary = { 184 / 255, 152 / 255, 238 / 255 },
}
style.defaults = SOULSTONE
style.colorNames = {
    { key = "background", label = "Background" },
    { key = "border", label = "Border" },
    { key = "accent", label = "Accent" },
    { key = "highlight", label = "Hover" },
    { key = "selection", label = "Selection" },
    { key = "secondary", label = "Secondary accent" },
}

local PRESET_KEYS = { "background", "border", "accent", "highlight", "selection", "secondary" }

local function Hex(value)
    return { tonumber(value:sub(2, 3), 16) / 255, tonumber(value:sub(4, 5), 16) / 255, tonumber(value:sub(6, 7), 16) / 255 }
end

local function Preset(name, list)
    local colors, index = {}, 0
    for value in list:gmatch("#%x+") do
        index = index + 1
        colors[PRESET_KEYS[index]] = Hex(value)
    end
    return { name = name, colors = colors }
end

style.presets = {
    { name = "Soulstone", colors = SOULSTONE },
    { name = "Mali", colors = MALI },
    Preset("Jazz 92", "#0c0018 #630066 #0095f2 #e700ff #73003d #00ffbb"),
    Preset("Fel", "#080f0a #284a22 #8fe63a #d4f070 #1e3a12 #a6f08a"),
    Preset("Terminal", "#040906 #1b3a22 #4cd97b #a6ffbf #10301a #7fe0a0"),
    Preset("Amber CRT", "#0b0803 #3d2a0e #ffb000 #ffd98a #3a2606 #ffc85c"),
    Preset("Rave 99", "#0a0614 #3b1a5a #ff3fa4 #3ff0ff #4a0f3a #c6ff3f"),
    Preset("Trance State", "#070b18 #22305e #4fc3ff #b18cff #1c2a66 #8fe9ff"),
    Preset("Midnight", "#0f1115 #33384a #7aa2f7 #bb9af7 #262b40 #a9c1ff"),
    Preset("Ember", "#120b08 #4a2a1a #ff8c42 #ffd166 #4a1e0e #ffb38a"),
    Preset("Graphite", "#121316 #3a3d45 #3d9cf0 #8cc8ff #1f3550 #e6e8ec"),
    Preset("Rosewater", "#151014 #4a3442 #f28fb0 #ffd1dc #4a2236 #f6c6d8"),
}

local db
local function Registry()
    return setmetatable({}, { __mode = "k" })
end

local flats, fonts, buttons, icons, fits = Registry(), Registry(), Registry(), Registry(), Registry()
local checks, fields, scrollBars, sliders, editBoxes, panels = Registry(), Registry(), Registry(), Registry(), Registry(), Registry()
local dividers, windows, tabs, dropdowns, swatches = Registry(), Registry(), Registry(), Registry(), Registry()
local repainters = {}

-- Call once at file load. All options are optional:
--   media        path to the addon's media folder, ending in a backslash
--   default      name of the preset that is this addon's default theme (moved to the top)
--   colorNames   { { key, label } ... } to relabel or rename the six colors
--   presets      a whole replacement preset list
function style.Configure(options)
    options = options or {}
    style.MEDIA = options.media or style.MEDIA
    style.colorNames = options.colorNames or style.colorNames
    style.presets = options.presets or style.presets
    if options.default then
        for index, preset in ipairs(style.presets) do
            if preset.name == options.default then
                table.remove(style.presets, index)
                table.insert(style.presets, 1, preset)
                break
            end
        end
    end
    style.defaults = style.presets[1].colors
end

function style.Init(savedVariables)
    db = savedVariables
    db.maliColors = type(db.maliColors) == "table" and db.maliColors or {}
    db.colorProfiles = type(db.colorProfiles) == "table" and db.colorProfiles or {}
end

function style.Color(key)
    local saved = db and db.maliColors[key]
    if type(saved) == "table" and saved[3] then
        return saved
    end
    return style.defaults[key]
end

function style.Accent()
    return style.Color("accent")
end

function style.SetColor(key, color)
    db.maliColors[key] = color and { color[1], color[2], color[3] } or nil
    style.Apply()
end

local function CurrentColors()
    local colors = {}
    for _, entry in ipairs(style.colorNames) do
        local color = style.Color(entry.key)
        colors[entry.key] = { color[1], color[2], color[3] }
    end
    return colors
end

style.CurrentColors = CurrentColors

function style.UseColors(colors)
    wipe(db.maliColors)
    for _, entry in ipairs(style.colorNames) do
        local color = colors[entry.key]
        if type(color) == "table" and color[3] then
            db.maliColors[entry.key] = { color[1], color[2], color[3] }
        end
    end
    style.Apply()
end

function style.ColorsMatch(colors)
    for _, entry in ipairs(style.colorNames) do
        local a, b = style.Color(entry.key), colors[entry.key] or style.defaults[entry.key]
        for index = 1, 3 do
            if math.abs(a[index] - b[index]) > 0.004 then
                return false
            end
        end
    end
    return true
end

function style.RestoreColors()
    wipe(db.maliColors)
    style.Apply()
end

function style.ProfileNames()
    local names = {}
    if not db then return names end
    for name in pairs(db.colorProfiles) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function style.SaveProfile(name)
    db.colorProfiles[name] = CurrentColors()
end

function style.LoadProfile(name)
    if db.colorProfiles[name] then
        style.UseColors(db.colorProfiles[name])
    end
end

function style.DeleteProfile(name)
    db.colorProfiles[name] = nil
end

function style.Profile(name)
    return db and db.colorProfiles[name]
end

function style.OnApply(callback)
    repainters[#repainters + 1] = callback
end

-- Text size

function style.Scale()
    local percent = db and tonumber(db.fontScale) or 100
    return math.max(MIN_SCALE, math.min(MAX_SCALE, percent / 100))
end

function style.WindowScale()
    return math.min(style.Scale(), MAX_WINDOW_SCALE)
end

function style.SetFontScale(percent)
    db.fontScale = math.max(MIN_SCALE * 100, math.min(MAX_SCALE * 100, math.floor(percent + 0.5)))
    style.Apply()
end

function style.SetGameFont(on)
    db.gameFont = on and true or nil
    style.Apply()
end

function style.UseInter()
    return not (db and db.gameFont) and not FALLBACK_LOCALES[GetLocale()]
end

function style.Icon(name)
    return style.MEDIA .. "icons\\" .. name
end

-- Pixel snapping

function style.Pixel(frame)
    local scale = frame and frame:GetEffectiveScale() or 1
    local height
    if GetPhysicalScreenSize then
        local _
        _, height = GetPhysicalScreenSize()
    end
    if height and height > 0 and scale and scale > 0 then
        return 768 / height / scale
    end
    return 1
end

local function Snap(frame)
    local pixel = style.Pixel(frame)
    for _, edge in ipairs(frame.maliEdges) do
        if edge.vertical then
            edge:SetWidth(frame.maliThickness * pixel)
        else
            edge:SetHeight(frame.maliThickness * pixel)
        end
    end
end

function style.Resnap()
    for frame in pairs(flats) do
        Snap(frame)
    end
    for line in pairs(dividers) do
        line:SetHeight(style.Pixel(line.owner))
    end
end

-- Flat fill and edges

local function Flat(frame, thickness)
    if frame.maliFill then return end
    frame.maliFill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    frame.maliFill:SetAllPoints()
    frame.maliEdges, frame.maliThickness = {}, thickness
    local function Edge(point, otherPoint, vertical)
        local edge = frame:CreateTexture(nil, "BORDER", nil, 7)
        edge:SetPoint(point, frame, point, 0, 0)
        edge:SetPoint(otherPoint, frame, otherPoint, 0, 0)
        if vertical then edge:SetWidth(thickness) else edge:SetHeight(thickness) end
        edge.vertical = vertical
        frame.maliEdges[#frame.maliEdges + 1] = edge
    end
    Edge("TOPLEFT", "TOPRIGHT", false)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
    Edge("TOPLEFT", "BOTTOMLEFT", true)
    Edge("TOPRIGHT", "BOTTOMRIGHT", true)
    flats[frame] = true
    Snap(frame)
    frame:HookScript("OnShow", Snap)
end

local function ShowFlat(frame, shown)
    frame.maliFill:SetShown(shown)
    for _, edge in ipairs(frame.maliEdges) do
        edge:SetShown(shown)
    end
end

local function Paint(frame, fill, border)
    frame.maliFill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    for _, edge in ipairs(frame.maliEdges) do
        edge:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
    end
end

local function HideTextures(frame, keep)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region ~= keep and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

-- Dividers

function style.Divider(frame, y, inset, width)
    local line = frame:CreateTexture(nil, "BORDER")
    line.owner = frame
    line:SetPoint("TOPLEFT", inset or 12, y)
    if width then
        line:SetWidth(width)
    else
        line:SetPoint("TOPRIGHT", -(inset or 12), y)
    end
    local border = style.Color("border")
    line:SetColorTexture(border[1], border[2], border[3], 0.8)
    line:SetHeight(style.Pixel(frame))
    dividers[line] = true
    return line
end

-- Windows that scale as a whole instead of scaling their text

local function Inside(object)
    local node = object
    if object.GetObjectType and object:GetObjectType() == "FontString" then
        node = object:GetParent()
    end
    for _ = 1, 40 do
        if not node then return false end
        if windows[node] then return true end
        node = node.maliScaleOwner or (node.GetParent and node:GetParent())
    end
    return false
end

local function WindowState(frame, base)
    frame:SetScale((base and base() or 1) * style.WindowScale())
end

function style.ScaleWindow(frame, base)
    windows[frame] = base or true
    WindowState(frame, base ~= nil and base or nil)
end

-- Fonts

local function HasCJK(text)
    return type(text) == "string" and (text:find("[\227-\237]") or text:find("\239[\164-\171\188-\191]")) ~= nil
end

local function FontState(fontString, info)
    local original = info.original
    local size = info.exempt and info.size or math.floor(info.size * style.Scale() + 0.5)
    if style.UseInter() and not info.cjk then
        fontString:SetFont(style.MEDIA .. FILE_NAMES[info.weight], size, "")
        local current = fontString:GetFont()
        if not current or not tostring(current):lower():find("inter-", 1, true) then
            fontString:SetFont(original[1], size, original[3] or "")
        end
    else
        fontString:SetFont(original[1], size, original[3] or "")
    end
end

function style.Font(fontString, size, weight)
    local file, height, flags = fontString:GetFont()
    fonts[fontString] = {
        original = { file, height, flags },
        size = size or height,
        weight = weight or "regular",
        exempt = Inside(fontString),
    }
    FontState(fontString, fonts[fontString])
    return fontString
end

function style.Text(fontString, object, bonus)
    if object then
        fontString:SetFontObject(object)
        local source = type(object) == "string" and _G[object] or object
        if type(source) == "table" and source.GetFont then
            local file, height, flags = source:GetFont()
            if file and height then fontString:SetFont(file, height, flags or "") end
        end
    end
    local name = type(object) == "string" and object or ""
    local size = name == "GameFontNormalLarge" and 15 or nil
    if bonus then
        local _, height = fontString:GetFont()
        size = (size or height or 12) + bonus
    end
    return style.Font(fontString, size, name:find("^GameFontNormal") and "medium" or "regular")
end

-- SetText for text the player or game supplies (item names, titles): Inter has no Chinese,
-- Japanese or Korean glyphs, so a string holding any of them uses its original font instead.
function style.SetText(fontString, text)
    local info = fonts[fontString]
    local cjk = HasCJK(text)
    if info and info.cjk ~= cjk then
        info.cjk = cjk
        FontState(fontString, info)
    end
    fontString:SetText(text)
end

function style.RefreshFonts()
    for fontString, info in pairs(fonts) do FontState(fontString, info) end
end

function style.ApplyFont(fontString)
    if fonts[fontString] then
        FontState(fontString, fonts[fontString])
    end
end

-- Panels

function style.Panel(frame, alpha)
    Flat(frame, 1)
    frame.maliFill:SetDrawLayer("BACKGROUND", -8)
    panels[frame] = alpha or 0.98
    local background, border = style.Color("background"), style.Color("border")
    Paint(frame, { background[1], background[2], background[3], panels[frame] }, border)
end

local function PanelState(frame, alpha)
    local background, border = style.Color("background"), style.Color("border")
    Paint(frame, { background[1], background[2], background[3], alpha }, border)
end

-- Buttons

local function Legacy(button)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local texture = button[getter] and button[getter](button)
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
    for _, field in ipairs({ "Left", "Middle", "Right", "Center", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        local texture = button[field]
        if type(texture) == "table" and texture.GetObjectType and texture:GetObjectType() == "Texture" then
            texture:SetAlpha(0)
        end
    end
end

local function FitState(button)
    local info = fits[button]
    local font = button:GetFontString()
    if not (info and font) then return end
    local width = info.base
    if style.Scale() ~= 1 and not Inside(button) then
        width = math.max(info.base, math.ceil(font:GetStringWidth() + info.pad))
    end
    if math.abs(button:GetWidth() - width) > 0.5 then
        button:SetWidth(width)
    end
end

function style.Fit(button, pad)
    if fits[button] then return end
    fits[button] = { base = button:GetWidth(), pad = pad or 16 }
    FitState(button)
end

local function TabState(button, font, enabled, active)
    ShowFlat(button, false)
    local line = active and style.Color("accent") or style.Color("highlight")
    button.maliUnderline:SetShown(active or (enabled and button.maliHover) or false)
    button.maliUnderline:SetColorTexture(line[1], line[2], line[3], active and 1 or 0.6)
    if font then
        if not enabled then font:SetTextColor(0.4, 0.39, 0.42)
        elseif active then font:SetTextColor(1, 0.82, 0)
        elseif button.maliHover then font:SetTextColor(1, 0.97, 0.9)
        else font:SetTextColor(0.66, 0.64, 0.7) end
    end
end

local function ButtonState(button)
    local font = button:GetFontString()
    Legacy(button)
    if fits[button] then FitState(button) end
    local enabled = button:IsEnabled()
    local active = enabled and button.maliActive
    if button.maliTab then
        TabState(button, font, enabled, active)
        return
    end
    ShowFlat(button, true)
    local background, border = style.Color("background"), style.Color("border")
    local highlight, accent = style.Color("highlight"), style.Color("accent")
    local fill = { background[1], background[2], background[3], 0.96 }
    local edge = { border[1], border[2], border[3], 1 }
    local text = { 0.9, 0.88, 0.84 }
    if button.maliDanger then
        edge, text = { 0.48, 0.2, 0.22, 1 }, { 0.94, 0.77, 0.75 }
    end
    if not enabled then
        edge, text = DISABLED_EDGE, { 0.4, 0.39, 0.42 }
    elseif button.maliDown then
        fill = { background[1] * 0.6, background[2] * 0.6, background[3] * 0.6, 1 }
        edge = accent
    elseif button.maliHover then
        fill = { highlight[1] * 0.19, highlight[2] * 0.18, highlight[3] * 0.21, 1 }
        edge = button.maliDanger and { 0.75, 0.3, 0.3, 1 } or highlight
        text = { 1, 0.97, 0.9 }
    elseif active then
        fill = { accent[1] * 0.12, accent[2] * 0.1, accent[3] * 0.1, 0.98 }
        edge = accent
    end
    Paint(button, fill, edge)
    if font then font:SetTextColor(text[1], text[2], text[3]) end
end

function style.Button(button)
    if buttons[button] then return button end
    buttons[button] = true
    Flat(button, 2)
    button:SetPushedTextOffset(0, -1)
    local font = button:GetFontString()
    if font then style.Font(font, nil, "medium") end
    button:HookScript("OnEnter", function(self) self.maliHover = true ButtonState(self) end)
    button:HookScript("OnLeave", function(self) self.maliHover, self.maliDown = false, false ButtonState(self) end)
    button:HookScript("OnMouseDown", function(self) self.maliDown = true ButtonState(self) end)
    button:HookScript("OnMouseUp", function(self) self.maliDown = false ButtonState(self) end)
    button:HookScript("OnShow", ButtonState)
    button:HookScript("OnHide", function(self) self.maliHover, self.maliDown = false, false end)
    if button:HasScript("OnEnable") then
        button:HookScript("OnEnable", ButtonState)
        button:HookScript("OnDisable", function(self) self.maliDown = false ButtonState(self) end)
    end
    if hooksecurefunc then
        hooksecurefunc(button, "SetText", ButtonState)
    end
    ButtonState(button)
    return button
end

function style.SetButtonActive(button, active)
    button.maliActive = active and true or false
    if buttons[button] then ButtonState(button) end
end

function style.SetButtonDanger(button, danger)
    button.maliDanger = danger and true or false
    if buttons[button] then ButtonState(button) end
end

-- A tab needs about 24px of height, or its 2px underline cuts through the label.
function style.Tab(button)
    style.Button(button)
    if button:GetHeight() < 24 then button:SetHeight(24) end
    if not button.maliUnderline then
        button.maliUnderline = button:CreateTexture(nil, "ARTWORK")
        button.maliUnderline:SetPoint("BOTTOMLEFT", 6, 1)
        button.maliUnderline:SetPoint("BOTTOMRIGHT", -6, 1)
        button.maliUnderline:SetHeight(2)
    end
    button.maliTab = true
    tabs[button] = true
    ButtonState(button)
    return button
end

-- Icon buttons

local REST, BRIGHT = { 0.81, 0.78, 0.85 }, { 1, 1, 1 }

local DANGER_FILL, DANGER_ICON = { 0.28, 0.05, 0.05, 1 }, { 1, 0.4, 0.4 }

local function IconState(button)
    local accent, background = style.Color("accent"), style.Color("background")
    local danger = button.maliDanger
    local outline = button.maliHover or button.maliDown or button.maliActive or danger
    ShowFlat(button, outline and true or false)
    local fill = { background[1] * 1.6, background[2] * 1.4, background[3] * 1.9, 1 }
    if danger then
        fill = DANGER_FILL
    elseif button.maliDown then
        fill = { accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 1 }
    end
    Paint(button, fill, danger and DANGER or accent)
    local tint = button.maliTint or REST
    if danger then
        tint = DANGER_ICON
    elseif button.maliHover then
        tint = BRIGHT
    elseif button.maliActive then
        tint = accent
    end
    button.icon:SetVertexColor(tint[1], tint[2], tint[3], button:IsEnabled() and 1 or 0.35)
end

function style.IconButton(parent, iconName, size, iconSize)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    Flat(button, 1)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(iconSize, iconSize)
    function button:SetIcon(name)
        self.icon:SetTexture(style.Icon(name))
    end
    button:SetIcon(iconName)
    button:HookScript("OnEnter", function(self) self.maliHover = true IconState(self) end)
    button:HookScript("OnLeave", function(self) self.maliHover, self.maliDown = false, false IconState(self) end)
    button:HookScript("OnMouseDown", function(self) self.maliDown = true IconState(self) end)
    button:HookScript("OnMouseUp", function(self) self.maliDown = false IconState(self) end)
    icons[button] = true
    IconState(button)
    return button
end

function style.SetIconActive(button, active)
    button.maliActive = active and true or false
    if icons[button] then IconState(button) end
end

function style.SetIconDanger(button, danger)
    button.maliDanger = danger and true or false
    if icons[button] then IconState(button) end
end

function style.CloseButton(parent, onClick)
    local button = style.IconButton(parent, "close", 22, 12)
    button:SetPoint("TOPRIGHT", -8, -8)
    button:SetScript("OnClick", onClick or function() parent:Hide() end)
    return button
end

-- Check boxes

local function CheckState(check)
    local box = check.maliBox
    local on, enabled = check:GetChecked() and true or false, check:IsEnabled()
    local background, border = style.Color("background"), style.Color("border")
    local highlight, accent = style.Color("highlight"), style.Color("accent")
    local edge = border
    if not enabled then edge = DISABLED_EDGE
    elseif on then edge = accent
    elseif check.maliHover then edge = highlight end
    Paint(box, { background[1] * 0.7, background[2] * 0.7, background[3] * 0.7, 1 }, edge)
    box.icon:SetShown(on)
    box.icon:SetVertexColor(accent[1], accent[2], accent[3], enabled and 1 or 0.4)
end

function style.Check(check)
    if checks[check] then return check end
    checks[check] = true
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
        "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
        local texture = check[getter] and check[getter](check)
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
    local box = CreateFrame("Frame", nil, check)
    box:SetSize(18, 18)
    box:SetPoint("CENTER", check, "CENTER", 0, 0)
    Flat(box, 1)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetPoint("CENTER")
    box.icon:SetSize(14, 14)
    box.icon:SetTexture(style.Icon("check"))
    check.maliBox = box
    check:HookScript("OnEnter", function(self) self.maliHover = true CheckState(self) end)
    check:HookScript("OnLeave", function(self) self.maliHover = false CheckState(self) end)
    check:HookScript("OnClick", CheckState)
    check:HookScript("OnShow", CheckState)
    if check:HasScript("OnEnable") then
        check:HookScript("OnEnable", CheckState)
        check:HookScript("OnDisable", CheckState)
    end
    if hooksecurefunc then
        hooksecurefunc(check, "SetChecked", CheckState)
    end
    CheckState(check)
    return check
end

-- Fields (the in-window dropdown button)

local function FieldState(box)
    local background, border = style.Color("background"), style.Color("border")
    local highlight, accent = style.Color("highlight"), style.Color("accent")
    local edge = box.maliOpen and accent or (box.maliHover and highlight or border)
    Paint(box, { background[1] * 0.7, background[2] * 0.7, background[3] * 0.7, 1 }, edge)
end

function style.Field(box)
    if fields[box] then return box end
    fields[box] = true
    Flat(box, 1)
    box:HookScript("OnEnter", function(self) self.maliHover = true FieldState(self) end)
    box:HookScript("OnLeave", function(self) self.maliHover = false FieldState(self) end)
    FieldState(box)
    return box
end

function style.SetFieldOpen(box, open)
    box.maliOpen = open and true or false
    if fields[box] then FieldState(box) end
end

-- Edit boxes

local function EditBoxState(box)
    local background, border = style.Color("background"), style.Color("border")
    local highlight, accent = style.Color("highlight"), style.Color("accent")
    local edge = box:HasFocus() and accent or (box.maliHover and highlight or border)
    Paint(box, { background[1] * 0.7, background[2] * 0.7, background[3] * 0.7, 1 }, edge)
    if box.maliPlaceholder then
        box.maliPlaceholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
    end
end

function style.EditBox(box, placeholder, withIcon)
    if editBoxes[box] then return box end
    editBoxes[box] = true
    HideTextures(box)
    Flat(box, 1)
    local inset = 6
    if withIcon then
        local icon = box:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexture(style.Icon("search"))
        icon:SetVertexColor(0.6, 0.58, 0.64)
        inset = 26
    end
    box:SetTextInsets(inset, 8, 0, 0)
    style.Font(box, 12, "regular")
    if placeholder then
        box.maliPlaceholder = style.Text(box:CreateFontString(nil, "OVERLAY"), "GameFontDisableSmall")
        box.maliPlaceholder:SetPoint("LEFT", inset, 0)
        box.maliPlaceholder:SetText(placeholder)
    end
    for _, script in ipairs({ "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged" }) do
        box:HookScript(script, EditBoxState)
    end
    box:HookScript("OnEnter", function(self) self.maliHover = true EditBoxState(self) end)
    box:HookScript("OnLeave", function(self) self.maliHover = false EditBoxState(self) end)
    EditBoxState(box)
    return box
end

-- Scroll bars

local function FindScrollBar(scroll)
    if type(scroll.ScrollBar) == "table" then return scroll.ScrollBar end
    local name = scroll.GetName and scroll:GetName()
    if name and _G[name .. "ScrollBar"] then return _G[name .. "ScrollBar"] end
    for _, child in ipairs({ scroll:GetChildren() }) do
        if child:GetObjectType() == "Slider" then return child end
    end
end

local function ScrollBarState(bar)
    local thumb = bar:GetThumbTexture()
    if not thumb then return end
    local highlight, background = style.Color("highlight"), style.Color("background")
    thumb:SetColorTexture(highlight[1], highlight[2], highlight[3], 0.75)
    thumb:SetSize(5, 40)
    bar.maliTrack:SetColorTexture(background[1] * 2, background[2] * 2, background[3] * 2.2, 0.8)
end

function style.Scroll(scroll)
    local bar = FindScrollBar(scroll)
    if not bar or scrollBars[bar] or not bar.GetThumbTexture then return bar end
    scrollBars[bar] = true
    for _, child in ipairs({ bar:GetChildren() }) do
        if child:GetObjectType() == "Button" then
            child:SetAlpha(0)
            child:EnableMouse(false)
        end
    end
    HideTextures(bar, bar:GetThumbTexture())
    bar.maliTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.maliTrack:SetPoint("TOP", 0, 0)
    bar.maliTrack:SetPoint("BOTTOM", 0, 0)
    bar.maliTrack:SetWidth(3)
    ScrollBarState(bar)
    return bar
end

-- Sliders

local function SliderState(bar)
    local thumb = bar:GetThumbTexture()
    local accent, background = style.Color("accent"), style.Color("background")
    local low, high = bar:GetMinMaxValues()
    local span = (high or 0) - (low or 0)
    local ratio = span > 0 and math.max(0, math.min(1, (bar:GetValue() - low) / span)) or 0
    bar.maliTrack:SetColorTexture(background[1] * 2.4, background[2] * 2.4, background[3] * 2.6, 1)
    bar.maliFill:SetColorTexture(accent[1], accent[2], accent[3], 0.85)
    bar.maliFill:SetWidth(math.max(1, ratio * (bar:GetWidth() or 0)))
    if thumb then
        local tint = bar.maliHover and { 1, 0.97, 0.9 } or { 0.81, 0.78, 0.85 }
        thumb:SetColorTexture(tint[1], tint[2], tint[3], 1)
        thumb:SetSize(8, 16)
    end
end

function style.Slider(bar)
    if sliders[bar] or not bar.GetThumbTexture then return bar end
    sliders[bar] = true
    if bar.SetBackdrop then pcall(bar.SetBackdrop, bar, nil) end
    HideTextures(bar, bar:GetThumbTexture())
    bar.maliTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.maliTrack:SetPoint("LEFT", 0, 0)
    bar.maliTrack:SetPoint("RIGHT", 0, 0)
    bar.maliTrack:SetHeight(4)
    bar.maliFill = bar:CreateTexture(nil, "BORDER")
    bar.maliFill:SetPoint("LEFT", bar.maliTrack, "LEFT", 0, 0)
    bar.maliFill:SetHeight(4)
    bar:HookScript("OnValueChanged", SliderState)
    bar:HookScript("OnEnter", function(self) self.maliHover = true SliderState(self) end)
    bar:HookScript("OnLeave", function(self) self.maliHover = false SliderState(self) end)
    bar:HookScript("OnShow", SliderState)
    bar:HookScript("OnSizeChanged", SliderState)
    SliderState(bar)
    return bar
end

-- Color swatches

local function SwatchState(button)
    local color = button.maliColor or { 0.5, 0.5, 0.5 }
    local edge = style.Color(button.maliHover and "highlight" or "border")
    Paint(button, { color[1], color[2], color[3], 1 }, { edge[1], edge[2], edge[3], 1 })
end

function style.Swatch(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size or 18, size or 18)
    Flat(button, 1)
    swatches[button] = true
    button:HookScript("OnEnter", function(self) self.maliHover = true SwatchState(self) end)
    button:HookScript("OnLeave", function(self) self.maliHover = false SwatchState(self) end)
    function button:SetColor(r, g, b)
        self.maliColor = { r, g, b }
        SwatchState(self)
    end
    SwatchState(button)
    return button
end

-- Color chips

local CHIP_KEYS = { "background", "accent", "highlight", "secondary" }

function style.Chip(parent)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(30, 10)
    local edge = chip:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(1, 1, 1, 0.25)
    chip.parts = {}
    for index = 1, #CHIP_KEYS do
        local part = chip:CreateTexture(nil, "ARTWORK")
        part:SetSize(30 / #CHIP_KEYS, 10)
        part:SetPoint("LEFT", (index - 1) * 30 / #CHIP_KEYS, 0)
        chip.parts[index] = part
    end
    function chip:SetColors(colors)
        for index, key in ipairs(CHIP_KEYS) do
            local color = colors and colors[key] or style.Color(key)
            self.parts[index]:SetColorTexture(color[1], color[2], color[3], 1)
        end
    end
    return chip
end

-- Dropdown with sections, chips, a current row and optional delete buttons

local function DropdownState(dd)
    local background, border = style.Color("background"), style.Color("border")
    local highlight, accent = style.Color("highlight"), style.Color("accent")
    local edge = dd.menu:IsShown() and accent or (dd.maliHover and highlight or border)
    if not dd:IsEnabled() then
        edge = DISABLED_EDGE
    end
    Paint(dd, { background[1] * 0.7, background[2] * 0.7, background[3] * 0.7, 1 }, edge)
    local text = dd:IsEnabled() and (dd.maliHover and { 1, 0.97, 0.9 } or { 0.9, 0.88, 0.84 }) or { 0.4, 0.39, 0.42 }
    dd.label:SetTextColor(text[1], text[2], text[3])
    dd.arrow:SetVertexColor(text[1], text[2], text[3])
    dd.chip:SetAlpha(dd:IsEnabled() and 1 or 0.35)
    Paint(dd.menu, { background[1], background[2], background[3], 0.98 }, border)
    if dd.menu.divider then
        dd.menu.divider:SetColorTexture(border[1], border[2], border[3], 1)
    end
end

local function MenuRow(dd, index)
    local menu = dd.menu
    if menu.rows[index] then
        return menu.rows[index]
    end
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(20)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.chip = style.Chip(row)
    row.chip:SetPoint("LEFT", 10, 0)
    row.text = style.Font(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    row.text:SetJustifyH("LEFT")
    row.delete = style.IconButton(row, "close", 18, 10)
    row.delete:SetPoint("RIGHT", -4, 0)
    row.delete.maliTint = { 0.85, 0.35, 0.35 }
    local function hover(on)
        row.hover:SetShown(on and not (row.item.header or row.item.inert))
        row.delete:SetAlpha(on and 1 or 0.3)
        local color = on and style.Color("highlight") or (row.item.current and style.Color("accent") or { 0.9, 0.88, 0.84 })
        if row.item.header or row.item.inert then
            color = { 0.55, 0.53, 0.6 }
        end
        row.text:SetTextColor(color[1], color[2], color[3])
    end
    row.SetHover = hover
    row:SetScript("OnEnter", function() hover(true) end)
    row:SetScript("OnLeave", function() hover(row.delete:IsMouseOver()) end)
    row.delete:HookScript("OnEnter", function() hover(true) end)
    row.delete:HookScript("OnLeave", function() hover(row:IsMouseOver()) end)
    row:SetScript("OnClick", function()
        if row.item.header or row.item.inert then
            return
        end
        menu:Hide()
        if dd.onSelect then
            dd.onSelect(row.item)
        end
    end)
    row.delete:SetScript("OnClick", function()
        if dd.onDelete then
            dd.onDelete(row.item)
        end
        dd:Refresh()
    end)
    menu.rows[index] = row
    return row
end

local function BuildMenu(dd)
    local menu = dd.menu
    local items = dd.getItems and dd.getItems() or {}
    local y, dividerY = -4, nil
    local highlight = style.Color("highlight")
    for index, item in ipairs(items) do
        local row = MenuRow(dd, index)
        row.item = item
        row:ClearAllPoints()
        if item.header and index > 1 then
            y = y - 5
            dividerY = y
            y = y - 4
        end
        row:SetPoint("TOPLEFT", 1, y)
        row:SetPoint("TOPRIGHT", -1, y)
        row:SetHeight(item.header and 18 or 20)
        row.hover:SetColorTexture(highlight[1], highlight[2], highlight[3], 0.14)
        row.chip:SetShown(item.colors ~= nil)
        if item.colors then
            row.chip:SetColors(item.colors)
        end
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", item.colors and 48 or 10, 0)
        row.text:SetPoint("RIGHT", -26, 0)
        row.text:SetText(item.header and string.upper(item.header) or item.text)
        row.delete:SetShown(item.deletable and true or false)
        row.delete:EnableMouse(item.deletable and true or false)
        style.ApplyFont(row.text)
        row.SetHover(false)
        row:Show()
        y = y - (item.header and 18 or 20)
    end
    for index = #items + 1, #menu.rows do
        menu.rows[index]:Hide()
    end
    if not menu.divider then
        menu.divider = menu:CreateTexture(nil, "ARTWORK")
        menu.divider:SetHeight(1)
    end
    menu.divider:SetShown(dividerY ~= nil)
    if dividerY then
        menu.divider:ClearAllPoints()
        menu.divider:SetPoint("TOPLEFT", 6, dividerY)
        menu.divider:SetPoint("TOPRIGHT", -6, dividerY)
    end
    menu:SetHeight(-y + 4)
    DropdownState(dd)
end

function style.Dropdown(parent, width)
    local dd = CreateFrame("Button", nil, parent)
    dd:SetSize(width, 24)
    Flat(dd, 1)
    dd.chip = style.Chip(dd)
    dd.chip:SetPoint("LEFT", 9, 0)
    dd.chip:Hide()
    dd.label = style.Font(dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    dd.label:SetJustifyH("LEFT")
    dd.arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.arrow:SetSize(12, 12)
    dd.arrow:SetPoint("RIGHT", -8, 0)
    dd.arrow:SetTexture(style.Icon("chevron-down"))

    local menu = CreateFrame("Frame", nil, UIParent)
    menu.maliScaleOwner = dd
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.rows = {}
    Flat(menu, 1)
    dd.menu = menu
    menu:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not dd:IsMouseOver() then
            self:Hide()
        end
    end)
    menu:SetScript("OnHide", function() DropdownState(dd) end)
    menu:SetScript("OnShow", function() DropdownState(dd) end)

    function dd:SetValue(text, colors)
        self.chip:SetShown(colors ~= nil)
        if colors then
            self.chip:SetColors(colors)
        end
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", colors and 47 or 9, 0)
        self.label:SetPoint("RIGHT", -24, 0)
        self.label:SetText(text)
    end
    function dd:Refresh()
        if self.menu:IsShown() then
            BuildMenu(self)
        end
        DropdownState(self)
    end
    function dd:Close()
        self.menu:Hide()
    end
    local setEnabled = dd.SetEnabled
    function dd:SetEnabled(enabled)
        setEnabled(self, enabled)
        if not enabled then self.menu:Hide() end
        DropdownState(self)
    end
    dd:SetScript("OnClick", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
        else
            local parentScale = UIParent:GetEffectiveScale()
            self.menu:SetScale(parentScale > 0 and self:GetEffectiveScale() / parentScale or 1)
            BuildMenu(self)
            self.menu:Show()
        end
    end)
    dd:SetScript("OnEnter", function(self) self.maliHover = true DropdownState(self) end)
    dd:SetScript("OnLeave", function(self) self.maliHover = false DropdownState(self) end)
    dd:HookScript("OnHide", function(self) self.menu:Hide() end)
    dropdowns[dd] = true
    DropdownState(dd)
    return dd
end

-- Repaint

function style.Apply()
    for frame, base in pairs(windows) do
        WindowState(frame, base ~= true and base or nil)
    end
    style.Resnap()
    for fontString, info in pairs(fonts) do FontState(fontString, info) end
    for frame, alpha in pairs(panels) do PanelState(frame, alpha) end
    for button in pairs(buttons) do ButtonState(button) end
    for button in pairs(icons) do IconState(button) end
    for check in pairs(checks) do CheckState(check) end
    for box in pairs(fields) do FieldState(box) end
    for box in pairs(editBoxes) do EditBoxState(box) end
    for bar in pairs(scrollBars) do ScrollBarState(bar) end
    for bar in pairs(sliders) do SliderState(bar) end
    for button in pairs(swatches) do SwatchState(button) end
    for dd in pairs(dropdowns) do dd:Refresh() end
    for _, callback in ipairs(repainters) do
        callback()
    end
end

-- Color picker with live preview; Cancel restores

function style.PickColor(key, onChange)
    local picker = ColorPickerFrame
    if not picker or not picker.SetupColorPickerAndShow then
        return false
    end
    local old = db.maliColors[key]
    local start = style.Color(key)
    picker:SetupColorPickerAndShow({
        r = start[1], g = start[2], b = start[3], hasOpacity = false,
        swatchFunc = function()
            local r, g, b = picker:GetColorRGB()
            style.SetColor(key, { r, g, b })
            if onChange then onChange() end
        end,
        cancelFunc = function()
            db.maliColors[key] = old
            style.Apply()
            if onChange then onChange() end
        end,
    })
    return true
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
    style.Resnap()
end)
