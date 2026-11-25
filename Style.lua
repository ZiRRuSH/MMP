-- MaliMusicPlayer styles: "mali" (flat dark panels, default) and "classic" (stock Blizzard look).
-- Player.lua registers its frames here; Apply() repaints everything when the style or a color changes.

local style = {}
MaliMusicPlayerStyle = style

style.defaults = {
    background = { 0.055, 0.055, 0.07 },
    border = { 0.3, 0.25, 0.4 },
    accent = { 242 / 255, 158 / 255, 59 / 255 },
    highlight = { 0.58, 0.47, 0.7 },
    selection = { 0.3, 0.2, 0.45 },
    openPlace = { 184 / 255, 152 / 255, 238 / 255 },
}
style.colorNames = {
    { key = "background", label = "Background" },
    { key = "border", label = "Border" },
    { key = "accent", label = "Accent (active tab, progress)" },
    { key = "highlight", label = "Hover" },
    { key = "selection", label = "Playing track" },
    { key = "openPlace", label = "Open place (Game Music)" },
}

local MEDIA = "Interface\\AddOns\\MaliMusicPlayer\\media\\"
style.MEDIA = MEDIA

local db
local buttons, tabs, panels, repainters = {}, {}, {}, {}
local fonts, iconButtons, toggles, flats = {}, {}, {}, {}

function style.Init(savedVariables)
    db = savedVariables
    if db.uiStyle ~= "classic" then
        db.uiStyle = "mali"
    end
    db.maliColors = type(db.maliColors) == "table" and db.maliColors or {}
    if db.maliFont ~= "game" then
        db.maliFont = "inter"
    end
end

function style.SetFontChoice(choice)
    db.maliFont = choice == "game" and "game" or "inter"
    style.Apply()
end

function style.FontChoice()
    return db and db.maliFont or "inter"
end

-- Size of one screen pixel in UI units for a frame, so 1px lines stay crisp at any UI scale.
function style.Pixel(frame)
    local scale = frame and frame:GetEffectiveScale() or 1
    local _, height = GetPhysicalScreenSize and GetPhysicalScreenSize()
    if height and height > 0 and scale > 0 then
        return 768 / height / scale
    end
    return 1
end

function style.IsMali()
    return not db or db.uiStyle ~= "classic"
end

function style.Color(key)
    local saved = db and db.maliColors[key]
    if type(saved) == "table" and saved[3] then
        return saved
    end
    return style.defaults[key]
end

function style.SetColor(key, color)
    db.maliColors[key] = color and { color[1], color[2], color[3] } or nil
    style.Apply()
end

function style.RestoreColors()
    wipe(db.maliColors)
    style.Apply()
end

function style.SetStyle(name)
    db.uiStyle = name == "classic" and "classic" or "mali"
    style.Apply()
end

-- Flat edges and fill, shared by buttons, tabs and panels.

local function Flat(frame, thickness)
    if frame.mmpFill then
        return
    end
    frame.mmpFill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    frame.mmpFill:SetAllPoints()
    frame.mmpEdges = {}
    frame.mmpThickness = thickness
    flats[frame] = true
    local function Edge(point, otherPoint, vertical)
        local edge = frame:CreateTexture(nil, "BORDER", nil, 7)
        edge:SetPoint(point, frame, point, 0, 0)
        edge:SetPoint(otherPoint, frame, otherPoint, 0, 0)
        if vertical then edge:SetWidth(thickness) else edge:SetHeight(thickness) end
        edge.mmpVertical = vertical
        frame.mmpEdges[#frame.mmpEdges + 1] = edge
    end
    Edge("TOPLEFT", "TOPRIGHT", false)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
    Edge("TOPLEFT", "BOTTOMLEFT", true)
    Edge("TOPRIGHT", "BOTTOMRIGHT", true)
end

local function ShowFlat(frame, shown)
    frame.mmpFill:SetShown(shown)
    for _, edge in ipairs(frame.mmpEdges) do
        edge:SetShown(shown)
    end
end

local function Paint(frame, fill, border)
    frame.mmpFill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    for _, edge in ipairs(frame.mmpEdges) do
        edge:SetColorTexture(border[1], border[2], border[3], border[4] or 1)
    end
end

-- Buttons (UIPanelButtonTemplate). Mali style hides the red art and draws a flat button.

local DANGER = { 0.92, 0.25, 0.25, 1 }

local LEGACY = { "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }

local function Legacy(button, alpha)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local texture = button[getter] and button[getter](button)
        if texture then
            texture:SetAlpha(alpha)
        end
    end
    for _, field in ipairs(LEGACY) do
        local texture = button[field]
        if type(texture) == "table" and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

local function ButtonState(button)
    local font = button.GetFontString and button:GetFontString()
    if not style.IsMali() then
        if button.mmpActive then button:LockHighlight() else button:UnlockHighlight() end
        Legacy(button, 1)
        ShowFlat(button, false)
        if font then
            if button.mmpDanger then
                font:SetTextColor(1, 0.3, 0.3)
            elseif button:IsEnabled() then
                font:SetTextColor(1, 0.82, 0)
            else
                font:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        return
    end
    Legacy(button, 0)
    ShowFlat(button, true)
    local background, border = style.Color("background"), style.Color("border")
    local fill = { background[1], background[2], background[3], 0.96 }
    local edge = { border[1], border[2], border[3], 1 }
    local text = { 0.9, 0.88, 0.84 }
    if button.mmpActive and button:IsEnabled() then
        local accent = style.Color("accent")
        edge = accent
        text = { 1, 0.82, 0 }
    end
    if button.mmpDanger then
        edge = DANGER
        text = { 1, 0.45, 0.45 }
    end
    if not button:IsEnabled() then
        edge = { 0.18, 0.17, 0.2, 0.75 }
        text = { 0.4, 0.39, 0.42 }
    elseif button.mmpDown then
        fill = { background[1] * 0.6, background[2] * 0.6, background[3] * 0.6, 1 }
        edge = style.Color("accent")
    elseif button.mmpHover then
        local highlight = style.Color("highlight")
        fill = { highlight[1] * 0.19, highlight[2] * 0.18, highlight[3] * 0.21, 1 }
        edge = highlight
        text = { 1, 0.97, 0.9 }
    end
    Paint(button, fill, edge)
    if font then
        font:SetTextColor(text[1], text[2], text[3])
    end
end

function style.Button(button)
    if buttons[button] then
        return button
    end
    buttons[button] = true
    Flat(button, 2)
    button:HookScript("OnEnter", function(self) self.mmpHover = true ButtonState(self) end)
    button:HookScript("OnLeave", function(self) self.mmpHover, self.mmpDown = false, false ButtonState(self) end)
    button:HookScript("OnMouseDown", function(self) self.mmpDown = true ButtonState(self) end)
    button:HookScript("OnMouseUp", function(self) self.mmpDown = false ButtonState(self) end)
    button:HookScript("OnShow", ButtonState)
    if button:HasScript("OnEnable") then
        button:HookScript("OnEnable", ButtonState)
        button:HookScript("OnDisable", ButtonState)
    end
    if hooksecurefunc then
        for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
            if type(button[method]) == "function" then
                hooksecurefunc(button, method, ButtonState)
            end
        end
    end
    ButtonState(button)
    return button
end

-- Tabs. Classic keeps the paper-doll tab art; Mali draws flat tabs with the active one in accent.

local function TabState(tab)
    local classic = not style.IsMali()
    for _, texture in ipairs({ tab.left, tab.middle, tab.right }) do
        texture:SetShown(classic)
    end
    ShowFlat(tab, false)
    tab.mmpUnderline:SetShown(not classic and (tab.mmpActive or tab.mmpHover))
    if classic then
        return
    end
    local accent, highlight = style.Color("accent"), style.Color("highlight")
    local line = tab.mmpActive and accent or highlight
    tab.mmpUnderline:SetColorTexture(line[1], line[2], line[3], tab.mmpActive and 1 or 0.6)
    if tab.mmpActive then
        tab.caption:SetTextColor(1, 0.82, 0)
    elseif tab.mmpHover then
        tab.caption:SetTextColor(1, 0.97, 0.9)
    else
        tab.caption:SetTextColor(0.66, 0.64, 0.7)
    end
end

function style.SetButtonDanger(button, danger)
    button.mmpDanger = danger and true or false
    ButtonState(button)
end

function style.SetButtonActive(button, active)
    button.mmpActive = active
    ButtonState(button)
end

function style.Tab(tab)
    tabs[tab] = true
    Flat(tab, 2)
    tab.mmpUnderline = tab:CreateTexture(nil, "ARTWORK")
    tab.mmpUnderline:SetPoint("BOTTOMLEFT", 10, 4)
    tab.mmpUnderline:SetPoint("BOTTOMRIGHT", -10, 4)
    tab.mmpUnderline:SetHeight(2)
    tab:HookScript("OnEnter", function(self) self.mmpHover = true TabState(self) end)
    tab:HookScript("OnLeave", function(self) self.mmpHover = false TabState(self) end)
end

function style.SetTabActive(tab, active)
    tab.mmpActive = active
    TabState(tab)
end

-- Panels: a flat backdrop drawn with textures, so no BackdropTemplate is needed.
-- template = regions/children that belong to a Blizzard template and show only in Classic.

function style.Panel(frame, template, alphaFunc, classicPaint)
    panels[frame] = { template = template or {}, alpha = alphaFunc, classic = classicPaint }
    Flat(frame, 1)
    frame.mmpFill:SetDrawLayer("BACKGROUND", -8)
end

local function PanelState(frame, info)
    local mali = style.IsMali()
    for _, item in ipairs(info.template) do
        item:SetShown(not mali)
    end
    if not mali and info.classic then
        ShowFlat(frame, false)
        info.classic(frame)
        return
    end
    ShowFlat(frame, mali)
    if mali then
        local background, border = style.Color("background"), style.Color("border")
        local alpha = info.alpha and info.alpha() or 0.98
        Paint(frame, { background[1], background[2], background[3], alpha }, { border[1], border[2], border[3], 1 })
    end
end

-- Fonts: Mali Style can use the bundled Inter; Classic (or "game font") keeps each string's own font.

local FONT_FILES = { regular = MEDIA .. "Inter-Regular.ttf", medium = MEDIA .. "Inter-Medium.ttf" }

function style.Font(fontString, size, weight)
    local file, height, flags = fontString:GetFont()
    fonts[fontString] = { original = { file, height, flags }, size = size, weight = weight or "regular" }
    return fontString
end

local function FontState(fontString, info)
    if style.IsMali() and style.FontChoice() == "inter" then
        fontString:SetFont(FONT_FILES[info.weight], info.size, "")
        if not fontString:GetFont() then
            fontString:SetFont(info.original[1], info.size, info.original[3] or "")
        end
    elseif style.IsMali() then
        fontString:SetFont(info.original[1], info.size + 1, info.original[3] or "")
    else
        fontString:SetFont(info.original[1], info.original[2], info.original[3] or "")
    end
end

function style.ApplyFont(fontString)
    if fonts[fontString] then
        FontState(fontString, fonts[fontString])
    end
end

-- Icon buttons: a tinted line icon with no box at rest; hover adds an accent outline.

local REST, BRIGHT = { 0.81, 0.78, 0.85 }, { 1, 1, 1 }

local function IconState(button)
    local accent, background = style.Color("accent"), style.Color("background")
    local outline = button.mmpEmphasis or button.mmpHover or button.mmpDown or button.mmpDanger
    ShowFlat(button, outline)
    local fill = { background[1] * 1.6, background[2] * 1.4, background[3] * 1.9, 1 }
    if button.mmpDanger then
        fill = { 0.28, 0.05, 0.05, 1 }
    elseif button.mmpDown then
        fill = { accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 1 }
    end
    Paint(button, fill, button.mmpDanger and DANGER or accent)
    local color = (button.mmpHover or button.mmpEmphasis) and BRIGHT or (button.mmpTint or REST)
    if button.mmpOn then
        color = accent
    end
    if button.mmpDanger then
        color = { 1, 0.4, 0.4 }
    end
    button.icon:SetVertexColor(color[1], color[2], color[3], button:IsEnabled() and 1 or 0.35)
end

function style.IconButton(parent, iconName, size, iconSize)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    Flat(button, 1)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER")
    button.icon:SetSize(iconSize, iconSize)
    function button:SetIcon(name)
        self.icon:SetTexture(MEDIA .. "icons\\" .. name)
    end
    button:SetIcon(iconName)
    button:HookScript("OnEnter", function(self) self.mmpHover = true IconState(self) end)
    button:HookScript("OnLeave", function(self) self.mmpHover, self.mmpDown = false, false IconState(self) end)
    button:HookScript("OnMouseDown", function(self) self.mmpDown = true IconState(self) end)
    button:HookScript("OnMouseUp", function(self) self.mmpDown = false IconState(self) end)
    iconButtons[button] = true
    IconState(button)
    return button
end

function style.IconRefresh(button)
    IconState(button)
end

-- Toggles: icon + label with a thin outline; "on" lights up in the accent color.

local function ToggleState(toggle)
    local accent, border, highlight = style.Color("accent"), style.Color("border"), style.Color("highlight")
    local edge = toggle.mmpOn and accent or (toggle.mmpHover and highlight or border)
    local background = style.Color("background")
    Paint(toggle, { background[1], background[2], background[3], 0.9 }, edge)
    local text = toggle.mmpOn and { 1, 0.82, 0 } or (toggle.mmpHover and { 1, 0.97, 0.9 } or { 0.66, 0.64, 0.7 })
    if not toggle:IsEnabled() then
        text = { 0.38, 0.37, 0.4 }
    end
    toggle.label:SetTextColor(text[1], text[2], text[3])
    local icon = toggle.mmpOn and accent or text
    toggle.icon:SetVertexColor(icon[1], icon[2], icon[3])
end

function style.Toggle(parent, iconName, caption, width)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(width, 24)
    Flat(toggle, 1)
    toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.icon:SetPoint("LEFT", 8, 0)
    toggle.icon:SetSize(14, 14)
    toggle.icon:SetTexture(MEDIA .. "icons\\" .. iconName)
    toggle.label = style.Font(toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
    toggle.label:SetPoint("LEFT", toggle.icon, "RIGHT", 6, 0)
    toggle.label:SetText(caption)
    toggle:HookScript("OnEnter", function(self) self.mmpHover = true ToggleState(self) end)
    toggle:HookScript("OnLeave", function(self) self.mmpHover = false ToggleState(self) end)
    if hooksecurefunc and type(toggle.SetEnabled) == "function" then
        hooksecurefunc(toggle, "SetEnabled", ToggleState)
    end
    function toggle:SetOn(on)
        self.mmpOn = on and true or false
        ToggleState(self)
    end
    toggles[toggle] = true
    ToggleState(toggle)
    return toggle
end

-- Search field: Mali draws a flat box with a magnifier and placeholder; Classic keeps InputBoxTemplate.

local editBoxes, scrollBars = {}, {}

local function EditBoxState(box)
    local mali = style.IsMali()
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local texture = box[key]
        if type(texture) == "table" and texture.SetAlpha then
            texture:SetAlpha(mali and 0 or 1)
        end
    end
    ShowFlat(box, mali)
    box.mmpIcon:SetShown(mali)
    box:SetTextInsets(mali and 26 or 0, mali and 8 or 0, 0, 0)
    local empty = (box:GetText() or "") == ""
    box.mmpPlaceholder:SetShown(empty and not box:HasFocus())
    box.mmpPlaceholder:ClearAllPoints()
    box.mmpPlaceholder:SetPoint("LEFT", mali and 26 or 2, 0)
    if mali then
        local background, border, highlight = style.Color("background"), style.Color("border"), style.Color("highlight")
        local edge = box:HasFocus() and style.Color("accent") or (box.mmpHover and highlight or border)
        Paint(box, { background[1] * 0.7, background[2] * 0.7, background[3] * 0.7, 1 }, edge)
        box.mmpIcon:SetVertexColor(0.6, 0.58, 0.64)
    end
end

function style.EditBox(box, placeholder)
    editBoxes[box] = true
    Flat(box, 1)
    box.mmpIcon = box:CreateTexture(nil, "ARTWORK")
    box.mmpIcon:SetSize(14, 14)
    box.mmpIcon:SetPoint("LEFT", 8, 0)
    box.mmpIcon:SetTexture(MEDIA .. "icons\\search")
    box.mmpPlaceholder = style.Font(box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 12)
    box.mmpPlaceholder:SetText(placeholder)
    box.mmpPlaceholder:SetTextColor(0.45, 0.43, 0.5)
    for _, script in ipairs({ "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged" }) do
        box:HookScript(script, EditBoxState)
    end
    box:HookScript("OnEnter", function(self) self.mmpHover = true EditBoxState(self) end)
    box:HookScript("OnLeave", function(self) self.mmpHover = false EditBoxState(self) end)
    EditBoxState(box)
end

-- Scroll bars: Mali hides the arrow buttons and draws a thin flat thumb on a faint track.

local function ScrollBarPart(bar, key)
    local value = bar[key]
    if type(value) == "table" then
        return value
    end
    local name = bar.GetName and bar:GetName()
    return name and _G[name .. key] or nil
end

local function ScrollBarState(bar)
    local mali = style.IsMali()
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local button = ScrollBarPart(bar, key)
        if button then
            button:SetAlpha(mali and 0 or 1)
            button:EnableMouse(not mali)
        end
    end
    local thumb = bar:GetThumbTexture()
    if not thumb then
        return
    end
    bar.mmpTrack:SetShown(mali)
    if mali then
        local highlight = style.Color("highlight")
        thumb:SetColorTexture(highlight[1], highlight[2], highlight[3], 0.75)
        thumb:SetSize(5, 40)
        local background = style.Color("background")
        bar.mmpTrack:SetColorTexture(background[1] * 2, background[2] * 2, background[3] * 2.2, 0.8)
    elseif bar.mmpThumb then
        thumb:SetTexture(bar.mmpThumb.file)
        thumb:SetTexCoord(unpack(bar.mmpThumb.coords))
        thumb:SetSize(bar.mmpThumb.width, bar.mmpThumb.height)
    end
end

function style.ScrollBar(bar)
    if not bar or scrollBars[bar] then
        return
    end
    scrollBars[bar] = true
    local thumb = bar:GetThumbTexture()
    if thumb then
        bar.mmpThumb = { file = thumb:GetTexture(), coords = { thumb:GetTexCoord() },
            width = thumb:GetWidth(), height = thumb:GetHeight() }
    end
    bar.mmpTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.mmpTrack:SetPoint("TOP", 0, 0)
    bar.mmpTrack:SetPoint("BOTTOM", 0, 0)
    bar.mmpTrack:SetWidth(3)
    ScrollBarState(bar)
end

function style.OnApply(callback)
    repainters[#repainters + 1] = callback
end

function style.Apply()
    for frame in pairs(flats) do
        local pixel = style.Pixel(frame)
        for _, edge in ipairs(frame.mmpEdges) do
            if edge.mmpVertical then
                edge:SetWidth(frame.mmpThickness * pixel)
            else
                edge:SetHeight(frame.mmpThickness * pixel)
            end
        end
    end
    for fontString, info in pairs(fonts) do
        FontState(fontString, info)
    end
    for button in pairs(iconButtons) do
        IconState(button)
    end
    for toggle in pairs(toggles) do
        ToggleState(toggle)
    end
    for box in pairs(editBoxes) do
        EditBoxState(box)
    end
    for bar in pairs(scrollBars) do
        ScrollBarState(bar)
    end
    for frame, info in pairs(panels) do
        PanelState(frame, info)
    end
    for button in pairs(buttons) do
        ButtonState(button)
    end
    for tab in pairs(tabs) do
        TabState(tab)
    end
    for _, callback in ipairs(repainters) do
        callback(style.IsMali())
    end
end

-- Color picker, same flow as MaliFishing: live preview, Cancel restores.

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

-- Keep 1px lines crisp when the UI scale or window size changes.
local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
scaleWatcher:SetScript("OnEvent", function()
    if db then
        style.Apply()
    end
end)
