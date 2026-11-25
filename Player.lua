-- MaliMusicPlayer 1.0.1

local VERSION = "1.0.1"
local style = MaliMusicPlayerStyle
-- Widgets that exist in only one style; style.OnApply shows the right set.
local classicOnly, maliOnly = {}, {}
local function classicWidget(widget)
    classicOnly[#classicOnly + 1] = widget
    return widget
end
local maliUpdate, maliSyncVolume, currentTab, layout

-- State

-- tracks holds your MP3s first (1..mp3Count), then the game music. Game tracks are added
-- place by place, so every place is a first..last range of indexes. The same game track
-- can sit in more than one place (a shared theme, for example); each copy is its own entry.
local tracks = {}
for _, track in ipairs(MaliMusicPlayerLibrary or {}) do
    tracks[#tracks + 1] = track
end
local mp3Count = #tracks

local gameCategories = {}  -- { name, key, places = { { name, key, first, last } } }
local gamePlaces = {}      -- flat list of every place, for lookups
-- The game music catalog lists WoW Forever's music files; other clients number their music
-- differently, so the Game Music tab is only filled in on Forever (interface 16xxx).
local catalog = MaliMusicPlayerGameMusic
local clientInterface = select(4, GetBuildInfo()) or 0
catalog = (clientInterface >= 16000 and clientInterface < 20000) and catalog or nil
if type(catalog) == "table" and type(catalog.categories) == "table" then
    for _, sourceCategory in ipairs(catalog.categories) do
        local category = { name = sourceCategory.name or "Other", places = {} }
        category.key = category.name
        for _, sourcePlace in ipairs(sourceCategory.places or {}) do
            local place = { name = sourcePlace.name or "Other", category = category, first = #tracks + 1 }
            place.key = category.key .. "/" .. place.name
            for _, entry in ipairs(sourcePlace.tracks or {}) do
                if entry.id then
                    tracks[#tracks + 1] = { title = entry.title or tostring(entry.id), fileDataID = entry.id,
                        place = place }
                end
            end
            place.last = #tracks
            if place.last >= place.first then
                category.places[#category.places + 1] = place
                gamePlaces[#gamePlaces + 1] = place
            end
        end
        if #category.places > 0 then
            gameCategories[#gameCategories + 1] = category
        end
    end
end

local browseGame = false
local gameMonitor = { status = C_Sound and C_Sound.IsPlaying }
function gameMonitor.duration(track)
    local samples = MaliMusicPlayerDB and MaliMusicPlayerDB.gameDurations
    return (track.fileDataID and samples and samples[track.fileDataID]) or track.duration or 0
end
local histories = { mp3 = { position = 0 }, game = { position = 0 } }
local retryTrack, retryPosition, playbackStatus
local menuShuffle, menuRepeat
local diagnosticLog = {}
local rebuild

local function sourceOf(index)
    return index > mp3Count and "game" or "mp3"
end
local db, current, selected, started = nil, nil, 1, 0
local playing, loading, soundHandle = false, false, nil
local diagnostics = false
local refresh, play, advance, sync, setCompact, togglePlayer, showTab, syncVolume
local filtered, rows, compactButtons = {}, {}, {}
local VISIBLE_ROWS, ROW_HEIGHT = 18, 24
local visibleRows = VISIBLE_ROWS
local PLAYING_MARK = "  |cff70cfff(playing)|r"
local MIN_VOLUME_PERCENT = 0.1

-- Utilities

local function say(message)
    print("|cff70cfffMaliMusicPlayer:|r " .. message)
end

local function trace(message)
    diagnosticLog[#diagnosticLog + 1] = message
    if #diagnosticLog > 100 then
        table.remove(diagnosticLog, 1)
    end
    if diagnostics then
        say("[audio] " .. message)
    end
end

local function safe(value)
    return (tostring(value or ""):gsub("|", "||"))
end

local function label(track)
    local artist = track.artist and track.artist ~= "" and track.artist .. " - " or ""
    return artist .. (track.title or "Untitled")
end

local function rememberSelection(index)
    if not tracks[index] then
        return
    end
    selected = index
    if db then
        local track = tracks[index]
        if track.path then
            db.selectedTrackPath = track.path
            db.selectedGameTrack = nil
        elseif track.place then
            db.selectedGameTrack = track.place.key .. "#" .. track.fileDataID
        end
    end
end

local function restoreSelection()
    selected = 1
    if db and type(db.selectedGameTrack) == "string" then
        for index = mp3Count + 1, #tracks do
            local track = tracks[index]
            if track.place.key .. "#" .. track.fileDataID == db.selectedGameTrack then
                selected = index
                return
            end
        end
        db.selectedGameTrack = nil
    end
    if db and type(db.selectedTrackPath) == "string" then
        for index, track in ipairs(tracks) do
            if track.path and track.path == db.selectedTrackPath then
                selected = index
                break
            end
        end
    end
    if db then
        db.selectedTrackPath = tracks[selected] and tracks[selected].path or nil
    end
end

local function musicVolume()
    return math.max(0, math.min(1, tonumber(GetCVar("Sound_MusicVolume")) or 0))
end

local function sliderPercent(value)
    value = tonumber(value) or MIN_VOLUME_PERCENT
    if value <= MIN_VOLUME_PERCENT then
        return MIN_VOLUME_PERCENT
    end
    return math.max(1, math.min(100, math.floor(value + 0.5)))
end

local function percentText(value)
    return (string.format("%.1f", value):gsub("%.0$", ""))
end

local function setMusicVolumePercent(value)
    local percent = sliderPercent(value)
    SetCVar("Sound_MusicVolume", percent / 100)
    trace("Volume: " .. percentText(percent) .. "%; CVar=" .. musicVolume())
    if syncVolume then
        syncVolume()
    end
end

local function clock(value)
    value = math.max(0, math.floor(value or 0))
    if value >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(value / 3600), math.floor(value / 60) % 60, value % 60)
    end
    return string.format("%d:%02d", math.floor(value / 60), value % 60)
end

local function opacity(value, minimum, default)
    return math.max(minimum, math.min(1, tonumber(value) or default))
end

local function stopHandle()
    if soundHandle then
        StopSound(soundHandle)
        soundHandle = nil
    end
end

local function font(parent, template, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function button(parent, caption, x, y, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 24)
    control:SetText(caption)
    control:SetScript("OnClick", callback)
    return style.Button(control)
end

local function restorePosition(frame, key)
    local position = db and db[key]
    if type(position) == "table" and position[1] and position[2]
        and type(position[3]) == "number" and type(position[4]) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    end
end

local function savePosition(frame, key)
    frame:StopMovingOrSizing()
    if db then
        local point, _, relativePoint, x, y = frame:GetPoint()
        db[key] = { point, relativePoint, x, y }
    end
end

-- Full Player

local f = CreateFrame("Frame", "MaliMusicPlayerFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(610, 700)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
    savePosition(self, "position")
end)
f.TitleText:SetText("MaliMusicPlayer")
f:Hide()

-- Everything BasicFrameTemplateWithInset drew (art, title bar, inset) shows only in Classic;
-- Mali style draws a flat panel instead. The close button stays in both.
do
    local template = {}
    for _, region in ipairs({ f:GetRegions() }) do
        template[#template + 1] = region
    end
    for _, child in ipairs({ f:GetChildren() }) do
        if child:GetObjectType() ~= "Button" then
            template[#template + 1] = child
        else
            classicWidget(child)
        end
    end
    if f.TitleText then
        classicWidget(f.TitleText)
    end
    f.maliTitle = style.Font(f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 15, "medium")
    f.maliTitle:SetPoint("TOPLEFT", 14, -11)
    f.maliTitle:SetText("MaliMusicPlayer")
    style.Panel(f, template)
    style.OnApply(function(mali)
        f.maliTitle:SetShown(mali)
    end)
end
table.insert(UISpecialFrames, "MaliMusicPlayerFrame")

local now = classicWidget(font(f, "GameFontHighlight", 16, -38, 575))
local timing = classicWidget(font(f, "GameFontNormalSmall", 16, -64, 575))
timing:SetText("Stopped")

local progress = classicWidget(CreateFrame("StatusBar", nil, f))
progress:SetPoint("TOPLEFT", 18, -87)
progress:SetSize(572, 7)
progress:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
progress:SetStatusBarColor(0.25, 0.7, 1)
progress:SetMinMaxValues(0, 1)
progress:SetValue(0)

local progressBackground = progress:CreateTexture(nil, "BACKGROUND")
progressBackground:SetAllPoints()
progressBackground:SetColorTexture(0.1, 0.1, 0.1, 1)
style.OnApply(function(mali)
    local accent, background = style.Color("accent"), style.Color("background")
    if mali then
        progress:SetStatusBarColor(accent[1], accent[2], accent[3])
        progressBackground:SetColorTexture(background[1] * 0.5, background[2] * 0.5, background[3] * 0.5, 1)
    else
        progress:SetStatusBarColor(0.25, 0.7, 1)
        progressBackground:SetColorTexture(0.1, 0.1, 0.1, 1)
    end
end)

local library = CreateFrame("Frame", nil, f)
library:SetAllPoints()
local settings = CreateFrame("Frame", nil, f)
settings:SetAllPoints()
settings:Hide()
local help = CreateFrame("Frame", nil, f)
help:SetAllPoints()
help:Hide()
local flavor = CreateFrame("Frame", nil, f)
flavor:SetAllPoints()
flavor:Hide()

-- Tabs

local tabs = {}

local function makeTab(index, key, caption, width)
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(width, 32)
    tab:SetFrameLevel(math.max(library:GetFrameLevel(), settings:GetFrameLevel()) + 5)
    tab:EnableMouse(true)
    if index == 1 then
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -103)
    else
        tab:SetPoint("TOPLEFT", tabs[index - 1], "TOPRIGHT", -6, 0)
    end
    tab.left = tab:CreateTexture(nil, "BACKGROUND")
    tab.left:SetPoint("TOPLEFT")
    tab.left:SetSize(20, 32)
    tab.right = tab:CreateTexture(nil, "BACKGROUND")
    tab.right:SetPoint("TOPRIGHT")
    tab.right:SetSize(20, 32)
    tab.middle = tab:CreateTexture(nil, "BACKGROUND")
    tab.middle:SetPoint("TOPLEFT", tab.left, "TOPRIGHT")
    tab.middle:SetPoint("BOTTOMRIGHT", tab.right, "BOTTOMLEFT")
    tab.caption = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.caption:SetPoint("CENTER")
    tab.caption:SetText(caption)
    style.Font(tab.caption, 12, "medium")
    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 8, -4)
    highlight:SetPoint("BOTTOMRIGHT", -8, 5)
    highlight:SetColorTexture(1, 1, 1, 0.08)
    tab:SetScript("OnClick", function()
        showTab(key)
    end)
    tab.key = key
    tabs[index] = tab
    style.Tab(tab)
end

makeTab(1, "library", "Library", 104)
makeTab(2, "game", "Game Music", 130)
makeTab(3, "settings", "Settings / About", 160)
makeTab(4, "flavor", "Flavor", 90)
makeTab(5, "help", "Help", 90)

showTab = function(which)
    currentTab = which
    local showLibrary = which == "library" or which == "game"
    library:SetShown(showLibrary)
    if showLibrary then
        browseGame = which == "game"
        if rebuild then
            rebuild()
        end
    end
    for name, content in pairs({ settings = settings, flavor = flavor, help = help }) do
        local holder = content.view or content
        holder:SetShown(which == name)
    end
    for _, tab in ipairs(tabs) do
        local active = tab.key == which
        local prefix = active and "Interface/PaperDollInfoFrame/UI-Character-ActiveTab-"
            or "Interface/PaperDollInfoFrame/UI-Character-InActiveTab-"
        tab.left:SetTexture(prefix .. "Left")
        tab.middle:SetTexture(prefix .. "Middle")
        tab.right:SetTexture(prefix .. "Right")
        tab.caption:SetTextColor(active and 1 or 0.85, active and 0.82 or 0.85, active and 0 or 0.85)
        tab.caption:ClearAllPoints()
        tab.caption:SetPoint("CENTER", 0, style.IsMali() and 0 or (active and 2 or -1))
        tab:Show()
        style.SetTabActive(tab, active)
    end
end

-- Library Controls

local search = CreateFrame("EditBox", nil, library, "InputBoxTemplate")
search:SetPoint("TOPLEFT", 23, -142)
search:SetPoint("RIGHT", library, "RIGHT", -152, 0)
search:SetHeight(24)
search:SetAutoFocus(false)
search:SetMaxLetters(150)
search:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
search:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)

local resultCount = style.Font(font(library, "GameFontNormalSmall", 477, -149, 110), 11)
resultCount:ClearAllPoints()
resultCount:SetPoint("TOPRIGHT", library, "TOPRIGHT", -24, -149)
resultCount:SetJustifyH("RIGHT")
resultCount:SetText("0 tracks")
style.EditBox(search, "Search tracks, places, categories")
library.gameNote = style.Font(library:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 13)
library.gameNote:SetPoint("TOPLEFT", 30, -200)
library.gameNote:SetPoint("RIGHT", -40, 0)
library.gameNote:SetJustifyH("LEFT")
library.gameNote:SetSpacing(4)
library.gameNote:SetText("Game Music is built for WoW Forever for now, so it isn't available in this version of the game.\n\n"
    .. "Your MP3 library works as usual on the Library tab.")
library.gameNote:Hide()
library.musicNote = style.Font(library:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 13)
library.musicNote:SetPoint("TOPLEFT", 30, -200)
library.musicNote:SetPoint("RIGHT", -40, 0)
library.musicNote:SetJustifyH("LEFT")
library.musicNote:SetSpacing(4)
library.musicNote:Hide()

local scroll = CreateFrame("ScrollFrame", "MaliMusicPlayerScroll", library, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -178)
scroll:SetPoint("BOTTOMRIGHT", -41, 90)

local function rowClick(self)
    local entry = self.track
    if type(entry) == "table" then
        -- Category or place header: open / close it.
        if db then
            db.gameExpanded = db.gameExpanded or {}
            db.gameExpanded[entry.key] = not db.gameExpanded[entry.key] or nil
            rebuild(true)
        end
    elseif entry then
        play(entry, nil, true)
    end
end

-- Rows are made on demand, so a taller window simply shows more of them.
local function getRow(index)
    if rows[index] then
        return rows[index]
    end
    local row = CreateFrame("Button", nil, library)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scroll, "RIGHT", -3, 0)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    row.chevron = row:CreateTexture(nil, "ARTWORK")
    row.chevron:SetSize(12, 12)
    row.chevron:Hide()
    row.speaker = row:CreateTexture(nil, "ARTWORK")
    row.speaker:SetSize(13, 13)
    row.speaker:SetTexture(style.MEDIA .. "icons\\volume")
    row.speaker:Hide()
    row.title = style.Font(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 12)
    row.title:SetPoint("RIGHT", -70, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.duration = style.Font(row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 11)
    row.duration:SetPoint("RIGHT", -4, 0)
    row.header = row:CreateTexture(nil, "BACKGROUND")
    row.header:SetAllPoints()
    row.header:Hide()
    row:SetScript("OnClick", rowClick)
    rows[index] = row
    style.ApplyFont(row.title)
    style.ApplyFont(row.duration)
    return row
end

for index = 1, VISIBLE_ROWS do
    getRow(index)
end
style.ScrollBar(scroll.ScrollBar or _G["MaliMusicPlayerScrollScrollBar"])

-- Compact Player

local compact = CreateFrame("Frame", "MaliMusicPlayerCompact", UIParent)
compact:SetSize(250, 56)
compact:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
compact:SetMovable(true)
compact:EnableMouse(true)
compact:SetClampedToScreen(true)
compact:Hide()

local compactBackground = compact:CreateTexture(nil, "BACKGROUND")
compactBackground:SetAllPoints()
local compactEdges = {}
for _, sides in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = compact:CreateTexture(nil, "BORDER")
    edge:SetPoint(sides[1])
    edge:SetPoint(sides[2])
    if #compactEdges < 2 then edge:SetHeight(1) else edge:SetWidth(1) end
    compactEdges[#compactEdges + 1] = edge
end
local titleViewport = CreateFrame("ScrollFrame", nil, compact)
titleViewport:SetPoint("TOPLEFT", 9, -7)
titleViewport:SetSize(162, 17)
titleViewport:EnableMouse(true)
local titleChild = CreateFrame("Frame", nil, titleViewport)
titleChild:SetSize(162, 17)
titleChild:EnableMouse(false)
titleViewport:SetScrollChild(titleChild)

local title = titleChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local fontPath = title:GetFont()
title:SetFont(fontPath, 11, "")
title:SetPoint("LEFT", titleChild, "LEFT", 0, 0)
title:SetWordWrap(false)

local compactTime = font(compact, "GameFontNormalSmall", 10, -34, 110)
local timeFont = compactTime:GetFont()
compactTime:SetFont(timeFont, 11, "")
compactTime:SetText("Stopped")
compactTime:SetWordWrap(false)
style.Font(title, 12)
style.Font(compactTime, 11)

local compactMoving = false

local function finishCompactMove()
    if not compactMoving then
        return
    end
    compactMoving = false
    savePosition(compact, "compactPosition")
end

-- Compact Title

local titleRepeat = titleChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
titleRepeat:SetFont(fontPath, 11, "")
titleRepeat:SetWordWrap(false)
style.Font(titleRepeat, 12)
titleRepeat:Hide()

local marqueeText, marqueeLimit, marqueePosition = nil, 0, 0
local marqueeDirection, marqueeWait, marqueeTick = 1, 2, 0
local marqueeCycle = 0

local function scrollMode()
    return db and db.compactScrollMode or "loop"
end

local function loopingTitle()
    return scrollMode() == "loop"
end

local function hideTitleTooltip()
    if GameTooltip:GetOwner() == titleViewport then
        GameTooltip:Hide()
    end
end

local function showTitleTooltip()
    if compactMoving or (db and db.compactTitleTooltip == false) then
        return
    end
    local index = current or selected
    if not tracks[index] then
        return
    end
    GameTooltip:SetOwner(titleViewport, "ANCHOR_TOP")
    GameTooltip:SetText(safe(label(tracks[index])), 1, 1, 1, 1, true)
    GameTooltip:Show()
end

titleViewport:SetScript("OnEnter", showTitleTooltip)
titleViewport:SetScript("OnLeave", hideTitleTooltip)
titleViewport:SetScript("OnHide", hideTitleTooltip)

local function resetMarquee()
    local width = math.ceil(title:GetStringWidth())
    local viewportWidth = titleViewport:GetWidth()
    marqueeLimit = math.max(0, width - viewportWidth)
    marqueePosition = 0
    marqueeDirection = 1
    marqueeWait = 2
    marqueeTick = 0
    title:SetWidth(math.max(width, 1))
    titleRepeat:SetText(marqueeText or "")
    titleRepeat:SetWidth(math.max(width, 1))
    marqueeCycle = width + 40
    titleRepeat:ClearAllPoints()
    titleRepeat:SetPoint("LEFT", titleChild, "LEFT", marqueeCycle, 0)
    local looping = loopingTitle() and marqueeLimit > 0
    titleRepeat:SetShown(looping)
    titleChild:SetWidth(looping and (marqueeCycle + width) or math.max(viewportWidth, width))
    titleViewport:UpdateScrollChildRect()
    titleViewport:SetHorizontalScroll(0)
end

local function setTitle(value)
    if value == marqueeText then
        return
    end
    marqueeText = value
    title:SetWidth(0)
    title:SetText(value)
    resetMarquee()
    if GameTooltip:GetOwner() == titleViewport and GameTooltip:IsShown() then
        showTitleTooltip()
    end
end

compact:SetScript("OnUpdate", function(self, elapsed)
    if compactMoving and not IsMouseButtonDown("LeftButton") then
        finishCompactMove()
    end
    if marqueeLimit <= 0 or scrollMode() == "static" then
        return
    end
    local looping = loopingTitle()
    if not looping and marqueeWait > 0 then
        marqueeWait = math.max(0, marqueeWait - elapsed)
        return
    end
    marqueeTick = marqueeTick + elapsed
    if marqueeTick < 1 / 30 then
        return
    end
    local delta = math.min(marqueeTick, 0.1)
    marqueeTick = 0
    if looping then
        marqueePosition = (marqueePosition + 24 * delta) % marqueeCycle
    else
        marqueePosition = marqueePosition + marqueeDirection * 24 * delta
        if marqueePosition >= marqueeLimit then
            marqueePosition = marqueeLimit
            marqueeDirection = -1
            marqueeWait = 2
        elseif marqueePosition <= 0 then
            marqueePosition = 0
            marqueeDirection = 1
            marqueeWait = 2
        end
    end
    titleViewport:SetHorizontalScroll(marqueePosition)
end)

-- Compact Appearance

local function applyOpacity()
    local hovered = false
    for _, control in ipairs(compactButtons) do
        if control.hovered then
            hovered = true
        end
        control:SetAlpha(control.hovered and 1 or opacity(db and db.compactButtonOpacity, 0.2, 0.75))
    end
    local textAlpha = hovered and 1 or opacity(db and db.compactTextOpacity, 0.2, 0.85)
    title:SetAlpha(textAlpha)
    titleRepeat:SetAlpha(textAlpha)
    compactTime:SetAlpha(textAlpha)
    local alpha = opacity(db and db.compactBackground, 0, 0.85)
    if style.IsMali() then
        local background, border = style.Color("background"), style.Color("border")
        compactBackground:SetColorTexture(background[1], background[2], background[3], alpha)
        for _, edge in ipairs(compactEdges) do
            edge:SetColorTexture(border[1], border[2], border[3], math.min(1, alpha * 2))
            edge:Show()
        end
    else
        compactBackground:SetColorTexture(0.025, 0.025, 0.025, alpha)
        for _, edge in ipairs(compactEdges) do
            edge:Hide()
        end
    end
end

-- Compact Buttons and Wheel Volume

local function showCompactButtonTooltip(control, caption)
    GameTooltip:SetOwner(control, "ANCHOR_TOP")
    GameTooltip:SetText(caption)
    GameTooltip:AddLine("Music volume: " .. percentText(musicVolume() * 100) .. "%", 1, 1, 1)
    GameTooltip:AddLine("Mousewheel: volume +/-1%", 0.75, 0.85, 1)
    GameTooltip:Show()
end

local function hoverHandlers(control, caption)
    control.tooltipCaption = caption
    control:HookScript("OnEnter", function(self)
        self.hovered = true
        applyOpacity()
        if caption then
            showCompactButtonTooltip(self, caption)
        end
    end)
    control:HookScript("OnLeave", function(self)
        self.hovered = false
        applyOpacity()
        GameTooltip:Hide()
    end)
    control:HookScript("OnHide", function(self)
        self.hovered = false
        applyOpacity()
        GameTooltip:Hide()
    end)
    control:EnableMouseWheel(true)
    control:HookScript("OnMouseWheel", function(self, delta)
        if delta == 0 then
            return
        end
        local value = musicVolume() * 100
        if delta > 0 then
            value = math.floor(value + 0.00001) + delta
        else
            value = math.ceil(value - 0.00001) + delta
        end
        setMusicVolumePercent(value)
        if self.hovered and caption then
            showCompactButtonTooltip(self, caption)
        end
    end)
    compactButtons[#compactButtons + 1] = control
end

local function iconButton(x, y, texture, tooltip, callback)
    local control = CreateFrame("Button", nil, compact)
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(23, 23)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.08, 0.08, 0.4)
    if texture == "PLAY" then
        for row = 0, 10 do
            local line = control:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(0.95, 0.8, 0.35, 1)
            line:SetPoint("TOPLEFT", control, "CENTER", -4, 5 - row)
            line:SetSize(11 - 2 * math.abs(row - 5), 1)
        end
    elseif texture then
        control:SetNormalTexture(texture)
        local icon = control:GetNormalTexture()
        icon:ClearAllPoints()
        icon:SetPoint("CENTER")
        icon:SetSize(21, 21)
    else
        local icon = control:CreateTexture(nil, "ARTWORK")
        icon:SetSize(9, 9)
        icon:SetPoint("CENTER")
        icon:SetColorTexture(0.95, 0.8, 0.35, 1)
    end
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    control:SetScript("OnClick", callback)
    hoverHandlers(control, tooltip)
    return control
end

-- Playback Display

local function updateCompactStatus()
    if GetCVar("Sound_EnableMusic") == "0" then
        compactTime:SetText("Music is off")
        compactTime:SetTextColor(1, 0.35, 0.35)
        return
    end
    if style.IsMali() then
        local accent = style.Color("accent")
        compactTime:SetTextColor(accent[1], accent[2], accent[3])
    else
        compactTime:SetTextColor(1, 0.82, 0)
    end
    if not playing or not current or not tracks[current] then
        compactTime:SetText(playbackStatus or "Stopped")
        return
    end
    local elapsed = math.max(0, GetTime() - started)
    if db and db.compactElapsedOnly then
        compactTime:SetText(clock(elapsed))
        return
    end
    local duration = gameMonitor.duration(tracks[current])
    compactTime:SetText(clock(elapsed) .. " / " .. (duration > 0 and clock(duration) or "--:--"))
end

local function updateTime()
    if not current then
        return
    end
    local duration = gameMonitor.duration(tracks[current])
    local elapsed = math.max(0, GetTime() - started)
    if duration > 0 then
        timing:SetText("Elapsed " .. clock(elapsed) .. "   |   Remaining -" .. clock(duration - elapsed)
            .. "   |   Total " .. clock(duration))
        progress:SetValue(math.min(1, elapsed / duration))
    else
        timing:SetText("Elapsed " .. clock(elapsed) .. "   |   Duration unknown")
        progress:SetValue(0)
    end
    updateCompactStatus()
    if maliUpdate then
        maliUpdate()
    end
end

refresh = function()
    FauxScrollFrame_Update(scroll, #filtered, visibleRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)
    local playingPlace = playing and current and tracks[current] and tracks[current].place
    local mali = style.IsMali()
    local accent = style.Color("accent")
    for index = 1, math.max(visibleRows, #rows) do
        local row = index <= visibleRows and getRow(index) or rows[index]
        local entry = index <= visibleRows and filtered[offset + index] or nil
        row.track = entry
        row.chevron:Hide()
        row.speaker:Hide()
        row.title:ClearAllPoints()
        row.title:SetPoint("RIGHT", -70, 0)
        if type(entry) == "table" then
            -- Mark only the header that holds the playing track, and only while it is
            -- closed; once it is open the track row itself carries the marker.
            local holds
            if entry.place then
                holds = playingPlace == entry.place
            else
                holds = playingPlace and playingPlace.category == entry.category
            end
            local marker = holds and not entry.open and PLAYING_MARK or ""
            local indent = entry.place and 20 or 2
            if mali then
                row.header:Hide()
                row.chevron:SetTexture(style.MEDIA .. "icons\\" .. (entry.open and "chevron-down" or "chevron-right"))
                row.chevron:ClearAllPoints()
                row.chevron:SetPoint("LEFT", indent, 0)
                local chevron = entry.place and (entry.open and style.Color("openPlace") or { 0.66, 0.64, 0.7 }) or accent
                row.chevron:SetVertexColor(chevron[1], chevron[2], chevron[3])
                row.chevron:Show()
                row.title:SetPoint("LEFT", indent + 18, 0)
            else
                row.header:SetShown(not entry.place)
                row.header:SetColorTexture(1, 0.82, 0, 0.07)
                row.title:SetPoint("LEFT", indent, 0)
            end
            local arrow = mali and "" or (entry.open and "[-] " or "[+] ")
            if entry.place then
                local name = safe(entry.place.name)
                if mali and entry.open then
                    local open = style.Color("openPlace")
                    name = string.format("|cff%02x%02x%02x%s|r", math.floor(open[1] * 255 + 0.5),
                        math.floor(open[2] * 255 + 0.5), math.floor(open[3] * 255 + 0.5), name)
                end
                row.title:SetText(arrow .. name .. marker)
                row.duration:SetText(entry.place.last - entry.place.first + 1 .. "")
            else
                row.title:SetText(arrow .. "|cffffd100" .. safe(entry.category.name) .. "|r" .. marker)
                row.duration:SetText(#entry.category.places .. (#entry.category.places == 1 and " place" or " places"))
            end
            row.duration:SetTextColor(0.6, 0.58, 0.64)
            if not mali then
                row.duration:SetTextColor(1, 0.82, 0)
            end
            row:Show()
        elseif entry then
            local track = tracks[entry]
            local isCurrent = playing and current == entry
            local indent = track.place and (mali and 44 or 40) or 4
            if isCurrent then
                local selection = mali and style.Color("selection") or { 0.25, 0.7, 1 }
                row.header:SetColorTexture(selection[1], selection[2], selection[3], mali and 0.7 or 0.12)
                row.header:Show()
            elseif mali and filtered.stripe and filtered.stripe[offset + index] then
                row.header:SetColorTexture(1, 1, 1, 0.035)
                row.header:Show()
            else
                row.header:Hide()
            end
            if mali and isCurrent then
                row.speaker:ClearAllPoints()
                row.speaker:SetPoint("LEFT", indent, 0)
                row.speaker:SetVertexColor(accent[1], accent[2], accent[3])
                row.speaker:Show()
                row.title:SetPoint("LEFT", indent + 18, 0)
                row.title:SetText("|cffffffff" .. safe(label(track)) .. "|r")
            else
                row.title:SetPoint("LEFT", indent, 0)
                row.title:SetText(isCurrent and ("|cffffffff" .. safe(label(track)) .. "|r" .. PLAYING_MARK) or safe(label(track)))
            end
            row.duration:SetText(gameMonitor.duration(track) > 0 and clock(gameMonitor.duration(track)) or "--:--")
            if mali then
                if isCurrent then
                    row.duration:SetTextColor(accent[1], accent[2], accent[3])
                else
                    row.duration:SetTextColor(0.6, 0.58, 0.64)
                end
            else
                row.duration:SetTextColor(1, 0.82, 0)
            end
            row:Show()
        else
            row.header:Hide()
            row:Hide()
        end
    end
    if current then
        local place = tracks[current].place
        local where = place and ("|cffaaaaaa" .. safe(place.category.name .. " > " .. place.name) .. " >|r ") or ""
        now:SetText((playing and "Playing: " or "Stopped: ") .. where .. safe(label(tracks[current])))
    elseif tracks[selected] then
        now:SetText("Selected: " .. safe(label(tracks[selected])))
    else
        now:SetText("Select a song to play.")
    end
    local index = current or selected
    setTitle(tracks[index] and safe(label(tracks[index])) or "MaliMusicPlayer")
    updateCompactStatus()
    if maliUpdate then
        maliUpdate()
    end
end

-- Your music lives in the companion add-on MaliMusic, made by the library updater.
function library.companionState()
    if MaliMusicPlayerLibrary then
        return "loaded"
    end
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not getInfo then
        return "unknown"
    end
    local ok, name, _, _, loadable, reason = pcall(getInfo, "MaliMusic")
    if not ok or not name or reason == "MISSING" then
        return "missing"
    end
    if reason == "INTERFACE_VERSION" then
        return "outdated"
    end
    return "disabled"
end

function library.musicHelp()
    local state = library.companionState()
    if state == "disabled" then
        return "Your music add-on \"MaliMusic\" is turned off.\n\n"
            .. "Enable it in the AddOns list at character select, then restart WoW."
    elseif state == "outdated" then
        return "Your music add-on \"MaliMusic\" is out of date.\n\n"
            .. "Run the library updater again (it refreshes it), then restart WoW."
    elseif state == "loaded" then
        return "No MP3s in your library yet.\n\n"
            .. "Put music in Interface/AddOns/MaliMusic/mp3, run the library updater, then restart WoW."
    end
    return "No music library yet.\n\nPut your MP3s in Interface/AddOns/MaliMusic/mp3 (create the folders if needed), "
        .. "then run the library updater in the MaliMusicPlayer folder (UpdateLibrary.cmd on Windows, "
        .. "UpdateLibrary.command on Mac, UpdateLibrary.sh on Linux) and restart WoW."
end

local function find(text, query)
    return string.find(string.lower(text or ""), query, 1, true) ~= nil
end

-- On the Game Music tab, filtered mixes header entries (tables) with track indexes
-- (numbers) so one scrolling list shows Category > Place > Tracks.
rebuild = function(keepOffset)
    local offset = keepOffset and FauxScrollFrame_GetOffset(scroll) or 0
    wipe(filtered)
    if library.gameNote then
        library.gameNote:Hide()
        library.musicNote:Hide()
    end
    local query = string.lower(search:GetText() or "")
    local total, matches = 0, 0
    if browseGame then
        local expanded = db and db.gameExpanded or {}
        local searching = query ~= ""
        for _, category in ipairs(gameCategories) do
            local categoryHit = searching and find(category.name, query)
            local categoryOpen = searching or expanded[category.key]
            local placeRows = {}
            for _, place in ipairs(category.places) do
                local placeHit = categoryHit or (searching and find(place.name, query))
                local hits = {}
                for index = place.first, place.last do
                    if not searching or placeHit or find(label(tracks[index]), query) then
                        hits[#hits + 1] = index
                    end
                end
                total = total + (place.last - place.first + 1)
                matches = matches + #hits
                if #hits > 0 then
                    local open = searching or expanded[place.key]
                    placeRows[#placeRows + 1] = { key = place.key, place = place, category = category, open = open }
                    if open then
                        for _, index in ipairs(hits) do
                            placeRows[#placeRows + 1] = index
                        end
                    end
                end
            end
            if #placeRows > 0 then
                filtered[#filtered + 1] = { key = category.key, category = category, open = categoryOpen }
                if categoryOpen then
                    for _, entry in ipairs(placeRows) do
                        filtered[#filtered + 1] = entry
                    end
                end
            end
        end
    else
        total = mp3Count
        if mp3Count == 0 and library.musicNote then
            library.musicNote:SetText(library.musicHelp())
            library.musicNote:Show()
        end
        for index = 1, mp3Count do
            if query == "" or find(label(tracks[index]), query) then
                filtered[#filtered + 1] = index
            end
        end
        matches = #filtered
    end
    if browseGame and total == 0 then
        resultCount:SetText("Forever only")
        library.gameNote:Show()
    elseif query == "" then
        resultCount:SetText(total .. (total == 1 and " track" or " tracks"))
    else
        resultCount:SetText(matches .. " of " .. total)
    end
    -- Stripe every other track, restarting under each header so places line up.
    filtered.stripe = {}
    local run = 0
    for position, entry in ipairs(filtered) do
        if type(entry) == "table" then
            run = 0
        else
            run = run + 1
            filtered.stripe[position] = not browseGame and run % 2 == 0
        end
    end
    offset = math.max(0, math.min(offset, #filtered - visibleRows))
    FauxScrollFrame_SetOffset(scroll, offset)
    if scroll.ScrollBar then
        scroll.ScrollBar:SetValue(offset * ROW_HEIGHT)
    end
    refresh()
end

scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refresh)
end)
search:SetScript("OnTextChanged", function()
    rebuild()
end)

-- Playback Controls

local function stop()
    playing = false
    retryTrack, retryPosition, playbackStatus = nil, nil, nil
    stopHandle()
    StopMusic()
    timing:SetText("Stopped")
    progress:SetValue(0)
    refresh()
end

local function audioBlock()
    if GetCVar("Sound_EnableAllSound") == "0" then
        return "Sound disabled"
    elseif GetCVar("Sound_EnableMusic") == "0" then
        return "Music disabled"
    elseif musicVolume() <= 0 then
        return "Muted externally"
    end
end

-- The player plays through WoW's music channel, so sound, music and music volume must all be on.
local failureNotice = { last = nil, time = 0 }
failureNotice.help = {
    ["Music disabled"] = "Music is off. The player plays through WoW's music channel, so turn music on to listen.",
    ["Sound disabled"] = "Game sound is off. Turn sound on to listen.",
    ["Muted externally"] = "Music volume is at 0%. Raise it to listen.",
    ["Playback failed"] = "That track would not play. The file may have been moved or renamed; press Play to retry.",
}
local function playbackFailure(index, position, status)
    stop()
    retryTrack, retryPosition, playbackStatus = index, position, status
    local help = failureNotice.help[status] or status
    timing:SetText(help)
    refresh()
    trace(status .. " track=" .. tostring(index))
    if status ~= failureNotice.last or GetTime() - failureNotice.time > 30 then
        say(help)
    end
    failureNotice.last, failureNotice.time = status, GetTime()
    return false
end

play = function(index, position, explicitNavigation)
    local track = tracks[index]
    if not track then
        say("No track selected or available.")
        return false
    end
    if not explicitNavigation and retryTrack == index then
        position = retryPosition
    end
    local blocked = audioBlock()
    if blocked then
        return playbackFailure(index, position, blocked)
    end
    stopHandle()
    playing = false
    PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg")
    local success, handle = PlaySoundFile(track.fileDataID or track.path, "Music")
    local source = sourceOf(index)
    trace("Play: source=" .. source .. " track=" .. index .. " fileDataID=" .. tostring(track.fileDataID)
        .. " success=" .. tostring(success) .. " handle=" .. tostring(handle))
    if not success or not handle then
        if handle then
            StopSound(handle)
        end
        return playbackFailure(index, position, "Playback failed")
    end
    local history = histories[source]
    if position then
        history.position = position
    elseif history[history.position] ~= index then
        local discarded = #history - history.position
        for slot = #history, history.position + 1, -1 do
            history[slot] = nil
        end
        history[#history + 1] = index
        local trimmed = #history > 11
        if trimmed then
            table.remove(history, 1)
        end
        history.position = #history
        trace("History: source=" .. source .. " discardedForward=" .. discarded
            .. " trimmedOldest=" .. (trimmed and 1 or 0))
    end
    current = index
    rememberSelection(index)
    retryTrack, retryPosition, playbackStatus = nil, nil, nil
    soundHandle = handle
    gameMonitor.seen, gameMonitor.interrupted = false, loading
    started = GetTime()
    playing = true
    updateTime()
    sync()
    refresh()
    return true
end

advance = function(direction, automatic)
    local outgoing = current or selected
    if not tracks[outgoing] then
        return false
    end
    local source = sourceOf(outgoing)
    local history = histories[source]
    -- MP3s move through your whole library; game tracks stay inside their place
    -- (Capitals > Darnassus, say), so Next, Shuffle and Repeat work like a small playlist.
    local first, count = 1, mp3Count
    local place = tracks[outgoing].place
    if place then
        first, count = place.first, place.last - place.first + 1
    end
    if count < 1 then
        return false
    end
    local shuffle = db and db.shuffle
    local repeatTrack = db and db.repeatTrack
    local index, position, reason = outgoing, nil, "sequential"
    if automatic and repeatTrack then
        reason = "repeat"
    elseif direction < 0 and history.position > 1 and tracks[history[history.position - 1]]
        and tracks[history[history.position - 1]].place == place then
        position = history.position - 1
        index, reason = history[position], "history-back"
    elseif direction > 0 and history.position < #history and not (automatic and shuffle)
        and tracks[history[history.position + 1]] and tracks[history[history.position + 1]].place == place then
        position = history.position + 1
        index, reason = history[position], "history-forward"
    elseif direction < 0 and shuffle then
        return false
    elseif shuffle and count > 1 then
        index = first + math.random(count - 1) - 1
        if index >= outgoing then
            index = index + 1
        end
        reason = "shuffle"
    else
        index = first + ((outgoing - first + direction) % count)
    end
    trace("Advance: " .. (automatic and "automatic" or "manual") .. " source=" .. source
        .. " from=" .. outgoing .. " to=" .. index .. " reason=" .. reason
        .. " repeat=" .. tostring(repeatTrack) .. " shuffle=" .. tostring(shuffle))
    return play(index, position, true)
end

local function togglePlaybackSetting(key, source)
    if db then
        db[key] = not db[key]
        trace("Setting: " .. key .. "=" .. tostring(db[key]) .. " via " .. source)
        sync()
    end
end

local function playSelected()
    play(retryTrack or current or selected)
end

classicWidget(button(library, "Previous", 16, -619, 88, function()
    advance(-1, false)
end))
classicWidget(button(library, "Play", 110, -619, 70, function()
    playSelected()
end))
classicWidget(button(library, "Stop", 186, -619, 70, stop))
classicWidget(button(library, "Next", 262, -619, 70, function()
    advance(1, false)
end))
local shuffle = classicWidget(button(library, "Shuffle: Off", 338, -619, 120, function()
    togglePlaybackSetting("shuffle", "main")
end))
local repeatButton = classicWidget(button(library, "Repeat: Off", 464, -619, 130, function()
    togglePlaybackSetting("repeatTrack", "main")
end))

sync = function()
    local game = current and sourceOf(current) == "game"
    local shuffleText = db and db.shuffle and "Shuffle: On" or "Shuffle: Off"
    local repeatText = db and db.repeatTrack and "Repeat: On" or "Repeat: Off"
    -- Game tracks can only move on by themselves if the client can tell when a sound
    -- ends (C_Sound.IsPlaying). Without it they play once, so Shuffle / Repeat do nothing.
    game = game and not gameMonitor.status
    if game then
        shuffleText, repeatText = "Shuffle: N/A", "Repeat: N/A"
    end
    local function apply(shuffleControl, repeatControl)
        shuffleControl:SetText(shuffleText)
        repeatControl:SetText(repeatText)
        if game then
            shuffleControl:Disable()
            repeatControl:Disable()
        else
            shuffleControl:Enable()
            repeatControl:Enable()
        end
    end
    apply(shuffle, repeatButton)
    if menuShuffle and menuRepeat then
        apply(menuShuffle, menuRepeat)
    end
end

-- Volume Slider

local volumeLabel = classicWidget(font(f, "GameFontNormalSmall", 18, -668, 160))
local volume = classicWidget(CreateFrame("Slider", nil, f, "OptionsSliderTemplate"))
volume:SetPoint("TOPLEFT", 180, -666)
volume:SetSize(210, 16)
volume:SetMinMaxValues(0, 100)
volume:SetValueStep(1)
if volume.SetObeyStepOnDrag then
    volume:SetObeyStepOnDrag(true)
end
local updatingVolume = false

syncVolume = function()
    updatingVolume = true
    local actual = musicVolume() * 100
    local displayed = sliderPercent(actual)
    volume:SetValue(displayed == MIN_VOLUME_PERCENT and 0 or displayed)
    if actual <= 0 then
        volumeLabel:SetText("Music volume: 0% (external)")
    elseif actual < MIN_VOLUME_PERCENT then
        volumeLabel:SetText("Music volume: <0.1%")
    else
        volumeLabel:SetText("Music volume: " .. percentText(actual) .. "%")
    end
    updatingVolume = false
    if maliSyncVolume then
        maliSyncVolume()
    end
end

volume:SetScript("OnValueChanged", function(self, value)
    if not updatingVolume then
        setMusicVolumePercent(value)
    end
end)
volume:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Music volume")
    GameTooltip:AddLine("0.1% minimum, then 1%-100% in whole steps. Use Stop for silence.", 1, 1, 1, true)
    GameTooltip:AddLine("Changing volume does not restart the track.", 1, 1, 1, true)
    GameTooltip:Show()
end)
volume:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
volume:SetScript("OnHide", function()
    GameTooltip:Hide()
end)

-- Music Setting

local musicToggle

local function syncMusicToggle()
    if musicToggle then
        local on = GetCVar("Sound_EnableMusic") == "1"
        musicToggle:SetText(on and "Music: On" or "Music: Off")
        style.SetButtonDanger(musicToggle, not on)
    end
    updateCompactStatus()
    if maliUpdate then
        maliUpdate()
    end
end

musicToggle = classicWidget(button(f, "Music: Off", 400, -665, 94, function()
    local enabled = GetCVar("Sound_EnableMusic") == "1"
    SetCVar("Sound_EnableMusic", enabled and "0" or "1")
    syncMusicToggle()
end))
musicToggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Enable / disable music")
    GameTooltip:AddLine("Changes WoW's Music setting directly. No keyboard shortcut required.", 1, 1, 1, true)
    GameTooltip:AddLine("Enable music here, then press Play to listen to your tracks.", 1, 1, 1, true)
    GameTooltip:AddLine("Does not change your volume or start / restart a track.", 1, 1, 1, true)
    GameTooltip:Show()
end)
musicToggle:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
musicToggle:SetScript("OnHide", function()
    GameTooltip:Hide()
end)
f:SetScript("OnShow", function()
    sync()
    syncVolume()
    syncMusicToggle()
end)

-- Player Modes

setCompact = function(enabled)
    if db then
        db.compactMode = enabled
    end
    if enabled then
        f:Hide()
        applyOpacity()
        updateCompactStatus()
        compact:Show()
    else
        compact:Hide()
        f:Show()
    end
end

f:HookScript("OnHide", function()
    if db and db.compactOnClose then
        db.compactMode = true
        applyOpacity()
        updateCompactStatus()
        compact:Show()
    else
        compact:Hide()
    end
end)

togglePlayer = function()
    if f:IsShown() then
        f:Hide()
    elseif compact:IsShown() then
        compact:Hide()
    elseif db and db.compactMode then
        setCompact(true)
    else
        showTab("library")
        setCompact(false)
    end
end

classicWidget(button(f, "Compact", 500, -665, 92, function()
    setCompact(true)
end))

local expandButton = classicWidget(iconButton(179, -4, "Interface/Buttons/UI-PlusButton-UP", "Open full player", function()
    showTab("library")
    setCompact(false)
end))
local playButton = classicWidget(iconButton(154, -29, "PLAY", nil, function()
    playSelected()
end))
local previousButton = classicWidget(iconButton(128, -29, "Interface/Buttons/UI-SpellbookIcon-PrevPage-Up", nil, function()
    advance(-1, false)
end))
local stopButton = classicWidget(iconButton(154, -29, nil, nil, stop))
local nextButton = classicWidget(iconButton(180, -29, "Interface/Buttons/UI-SpellbookIcon-NextPage-Up", nil, function()
    advance(1, false)
end))

-- Compact Dimensions

local function compactWidth(value)
    return math.max(180, math.min(360, math.floor((tonumber(value) or 250) + 0.5)))
end

local function applyCompactWidth(value)
    local width = compactWidth(value)
    compact:SetWidth(width)
    titleViewport:SetWidth(width - 48)
    compactTime:SetWidth(width - 120)
    expandButton:ClearAllPoints()
    expandButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -8, -4)
    playButton:ClearAllPoints()
    playButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -37, -29)
    previousButton:ClearAllPoints()
    previousButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -89, -29)
    stopButton:ClearAllPoints()
    stopButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -63, -29)
    nextButton:ClearAllPoints()
    nextButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -11, -29)
    resetMarquee()
end

-- Appearance Settings

font(settings, "GameFontNormal", 20, -147, 555):SetText("Compact appearance")
local opacityInitializing = false

local function opacityControl(y, caption, key, minimum)
    local captionText = font(settings, "GameFontHighlightSmall", 24, y, 240)
    local slider = CreateFrame("Slider", nil, settings, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 280, y)
    slider:SetSize(270, 16)
    slider:SetMinMaxValues(minimum, 100)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        captionText:SetText(caption .. ": " .. value .. "%")
        if db and not opacityInitializing then
            db[key] = value / 100
        end
        applyOpacity()
    end)
    return slider
end

local backgroundSlider = opacityControl(-174, "Background opacity", "compactBackground", 0)
local textSlider = opacityControl(-204, "Text opacity", "compactTextOpacity", 20)
local buttonSlider = opacityControl(-234, "Button opacity", "compactButtonOpacity", 20)
font(settings, "GameFontDisableSmall", 24, -264, 550):SetText(
    "Hover a compact button to brighten it and the title / timer to 100%."
)
font(settings, "GameFontHighlightSmall", 24, -285, 240):SetText("Title scrolling")
local scrollModeButton

local function syncScrollMode()
    local mode = scrollMode()
    scrollModeButton:SetText(mode == "static" and "Stationary"
        or (mode == "bounce" and "Back-and-forth" or "Continuous loop"))
end

scrollModeButton = button(settings, "Continuous loop", 280, -280, 270, function()
    if not db then
        return
    end
    local mode = scrollMode()
    db.compactScrollMode = mode == "loop" and "bounce" or (mode == "bounce" and "static" or "loop")
    syncScrollMode()
    resetMarquee()
end)
font(settings, "GameFontDisableSmall", 24, -310, 550):SetText(
    "Click to cycle: continuous / back-and-forth / stationary. Choice is saved."
)

local widthLabel = font(settings, "GameFontHighlightSmall", 24, -338, 240)
local widthSlider = CreateFrame("Slider", nil, settings, "OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT", 280, -336)
widthSlider:SetSize(270, 16)
widthSlider:SetMinMaxValues(180, 360)
widthSlider:SetValueStep(1)
if widthSlider.SetObeyStepOnDrag then
    widthSlider:SetObeyStepOnDrag(true)
end
widthSlider:SetScript("OnValueChanged", function(self, value)
    local width = compactWidth(value)
    widthLabel:SetText("Compact width: " .. width .. " px")
    if db and not opacityInitializing then
        db.compactWidth = width
    end
    applyCompactWidth(width)
end)
local widthNote = font(settings, "GameFontDisableSmall", 24, -363, 550)
widthNote:SetText(
    "180-360 px. Default: 250 px. Width updates immediately and is saved."
)

local fullOpacityLabel = font(settings, "GameFontHighlightSmall", 24, -390, 240)
local fullOpacitySlider = CreateFrame("Slider", nil, settings, "OptionsSliderTemplate")
fullOpacitySlider:SetPoint("TOPLEFT", 280, -388)
fullOpacitySlider:SetSize(270, 16)
fullOpacitySlider:SetMinMaxValues(33, 100)
fullOpacitySlider:SetValueStep(1)
if fullOpacitySlider.SetObeyStepOnDrag then
    fullOpacitySlider:SetObeyStepOnDrag(true)
end
fullOpacitySlider:SetScript("OnValueChanged", function(self, value)
    local alpha = opacity(math.floor(value + 0.5) / 100, 0.33, 1)
    fullOpacityLabel:SetText("Full player opacity: " .. math.floor(alpha * 100 + 0.5) .. "%")
    if db and not opacityInitializing then
        db.fullPlayerOpacity = alpha
    end
    f:SetAlpha(alpha)
end)
font(settings, "GameFontDisableSmall", 232, -414, 330):SetText(
    "Full player opacity: 33-100%; compact is separate."
)

-- Compact Display Settings

local titleTooltipCheck = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
titleTooltipCheck:SetPoint("TOPLEFT", 22, -430)
titleTooltipCheck:SetSize(24, 24)
font(settings, "GameFontHighlightSmall", 50, -437, 260):SetText("Show compact title tooltip")
titleTooltipCheck:SetScript("OnClick", function(self)
    if not db then
        return
    end
    db.compactTitleTooltip = self:GetChecked() and true or false
    if not db.compactTitleTooltip then
        hideTitleTooltip()
    end
end)

button(settings, "Reset Compact Position", 330, -430, 220, function()
    finishCompactMove()
    hideTitleTooltip()
    compact:ClearAllPoints()
    compact:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    if db then
        db.compactPosition = nil
    end
end)

local elapsedOnlyCheck = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
elapsedOnlyCheck:SetPoint("TOPLEFT", 22, -455)
elapsedOnlyCheck:SetSize(24, 24)
font(settings, "GameFontHighlightSmall", 50, -462, 500):SetText("Elapsed time only in compact display")
elapsedOnlyCheck:SetScript("OnClick", function(self)
    if not db then
        return
    end
    db.compactElapsedOnly = self:GetChecked() and true or false
    updateCompactStatus()
end)

-- Background Audio

local backgroundAudioCheck = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
backgroundAudioCheck:SetPoint("TOPLEFT", 22, -480)
backgroundAudioCheck:SetSize(24, 24)
font(settings, "GameFontHighlightSmall", 50, -487, 500):SetText("Allow music in background *")
local backgroundAudioNote = font(settings, "GameFontDisableSmall", 50, -507, 505)
backgroundAudioNote:SetWordWrap(true)
backgroundAudioNote:SetText(
    "* Recommended to prevent MP3 interruptions when switching away from WoW. "
        .. "Changes WoW's Sound in Background setting for all game audio."
)

local function syncBackgroundAudio()
    backgroundAudioCheck:SetChecked(GetCVar("Sound_EnableSoundWhenGameIsInBG") == "1")
end

backgroundAudioCheck:SetScript("OnClick", function(self)
    SetCVar("Sound_EnableSoundWhenGameIsInBG", self:GetChecked() and "1" or "0")
    syncBackgroundAudio()
end)
settings:HookScript("OnShow", syncBackgroundAudio)

-- Close Behavior

local compactOnCloseCheck = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
compactOnCloseCheck:SetPoint("TOPLEFT", 22, -538)
compactOnCloseCheck:SetSize(24, 24)
font(settings, "GameFontHighlightSmall", 50, -545, 500):SetText(
    "Switch to compact when closing the main player"
)
compactOnCloseCheck:SetScript("OnClick", function(self)
    if db then
        db.compactOnClose = self:GetChecked() and true or false
    end
end)

-- About

font(settings, "GameFontNormal", 20, -565, 555):SetText("About")
font(settings, "GameFontHighlightSmall", 24, -583, 555):SetText(
    "MaliMusicPlayer v" .. VERSION .. " - By Mali Gnosis, for Mali Gnosis."
)
local quote = font(settings, "GameFontHighlightSmall", 24, -600, 555)
quote:SetWordWrap(false)
quote:SetText('"If I throw a dog a bone, I don\'t want to know if it tastes good or not." - Brick Top')
local quoteFont = quote:GetFont()
for size = 11, 8, -0.5 do
    quote:SetFont(quoteFont, size, "")
    if quote:GetStringWidth() <= 555 then
        break
    end
end
font(settings, "GameFontDisableSmall", 24, -618, 555):SetText(
    "Released under the MIT License. See LICENSE.MD for details."
)
font(settings, "GameFontHighlightSmall", 24, -645, 55):SetText("GitHub:")

local repositoryURL = "https://github.com/ZiRRuSH/MMP"
local repository = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
repository:SetPoint("TOPLEFT", 86, -639)
repository:SetSize(475, 22)
repository:SetAutoFocus(false)
repository:SetMaxLetters(200)
repository:SetText(repositoryURL)
repository:SetCursorPosition(0)
local restoringRepository = false
repository:SetScript("OnTextChanged", function(self)
    if restoringRepository or self:GetText() == repositoryURL then
        return
    end
    restoringRepository = true
    self:SetText(repositoryURL)
    self:SetCursorPosition(0)
    restoringRepository = false
end)
repository:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
end)
repository:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
end)
repository:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
repository:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
repository:SetScript("OnHide", function(self)
    self:ClearFocus()
end)
showTab("library")

-- Help

font(help, "GameFontNormalLarge", 24, -150, 550):SetText("Adding your music")

local helpSteps = font(help, "GameFontHighlight", 24, -184, 550)
local helpFont = helpSteps:GetFont()
helpSteps:SetFont(helpFont, 14, "")
helpSteps:SetSpacing(5)
helpSteps:SetWordWrap(true)
helpSteps:SetText(
    "|cffffd1001. Add your MP3 files|r\n"
        .. "Put your music in (create the folders if needed):\n"
        .. "|cff70cfffInterface/AddOns/MaliMusic/mp3/|r\n"
        .. "Add-on updates never touch this folder.\n\n"
        .. "|cffffd1002. Update your library|r\n"
        .. "In |cff70cfffInterface/AddOns/MaliMusicPlayer/|r run |cff70cfffUpdateLibrary.cmd|r (Windows),\n"
        .. "|cff70cfffUpdateLibrary.command|r (Mac) or |cff70cfffUpdateLibrary.sh|r (Linux).\n\n"
        .. "|cffffd1003. Restart WoW|r\n"
        .. "Keep |cff70cfffMaliMusic|r enabled in the AddOns list."
)

local helpNote = font(help, "GameFontHighlight", 24, -184, 550)
helpNote:ClearAllPoints()
helpNote:SetPoint("TOPLEFT", helpSteps, "BOTTOMLEFT", 0, -24)
helpNote:SetFont(helpFont, 13, "")
helpNote:SetSpacing(4)
helpNote:SetWordWrap(true)
helpNote:SetText(
    "WoW cannot scan your music folder directly. Whenever you add, remove, or rename music, "
        .. "run the library updater again, then type |cff70cfff/reload|r."
)

local helpPause = font(help, "GameFontHighlight", 24, -184, 550)
helpPause:ClearAllPoints()
helpPause:SetPoint("TOPLEFT", helpNote, "BOTTOMLEFT", 0, -24)
helpPause:SetFont(helpFont, 13, "")
helpPause:SetSpacing(4)
helpPause:SetWordWrap(true)
helpPause:SetText(
    "|cffffd100Why no Pause / Resume?|r\n"
        .. "MaliMusicPlayer acts as a replacement soundtrack for WoW, "
        .. "suppressing the normal background music and playing your MP3s "
        .. "through the game's Music audio channel.\n\n"
        .. "WoW's addon audio controls let us start and stop tracks, "
        .. "but not pause them or resume from a saved position. "
        .. "Stop ends playback; Play starts the track again from the beginning. "
        .. "This is a limitation of the controls WoW provides to addons, "
        .. "not a missing player feature."
)

-- Flavor

font(flavor, "GameFontNormal", 20, -147, 555):SetText("UI style")
local styleButtons = {}
local syncFlavor

local function styleChoice(name, caption, x)
    local control = button(flavor, caption, x, -168, 150, function()
        style.SetStyle(name)
        syncFlavor()
    end)
    styleButtons[name] = control
end

styleChoice("mali", "Mali Style", 24)
styleChoice("classic", "Classic", 184)
font(flavor, "GameFontDisableSmall", 24, -200, 550):SetText(
    "Mali Style is a flat, dark look shared with MaliFishing. Classic is the standard Blizzard look."
)

font(flavor, "GameFontNormal", 20, -228, 555):SetText("Mali Style font")
local fontButtons = {}
for index, choice in ipairs({ { "inter", "Inter" }, { "game", "WoW font" } }) do
    fontButtons[choice[1]] = button(flavor, choice[2], 24 + (index - 1) * 160, -249, 150, function()
        style.SetFontChoice(choice[1])
        syncFlavor()
    end)
end
font(flavor, "GameFontDisableSmall", 24, -281, 550):SetText(
    "Inter is a clean font bundled with the add-on. WoW font matches the rest of your interface."
)

font(flavor, "GameFontNormal", 20, -309, 555):SetText("Mali Style colors")
local colorNote = font(flavor, "GameFontDisableSmall", 24, -329, 550)
local swatches = {}

for index, entry in ipairs(style.colorNames) do
    local y = -351 - (index - 1) * 30
    local swatch = CreateFrame("Button", nil, flavor)
    swatch:SetPoint("TOPLEFT", 26, y)
    swatch:SetSize(22, 22)
    local edge = swatch:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.7, 0.7, 0.7, 1)
    swatch.color = swatch:CreateTexture(nil, "ARTWORK")
    swatch.color:SetPoint("TOPLEFT", 2, -2)
    swatch.color:SetPoint("BOTTOMRIGHT", -2, 2)
    local highlight = swatch:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.2)
    swatch.label = font(flavor, "GameFontHighlightSmall", 58, y - 5, 400)
    swatch.label:SetText(entry.label)
    swatch:SetScript("OnClick", function()
        if not style.IsMali() then
            return
        end
        if not style.PickColor(entry.key, function() syncFlavor() end) then
            say("The color picker is not available on this client.")
        end
    end)
    swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.label)
        GameTooltip:AddLine(style.IsMali() and "Click to choose a color." or "Switch to Mali Style to change colors.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    swatch.key = entry.key
    swatches[#swatches + 1] = swatch
end

local restoreColors = button(flavor, "Restore default colors", 24, -351 - #swatches * 30 - 6, 200, function()
    style.RestoreColors()
    syncFlavor()
    say("Mali Style colors restored to the defaults.")
end)

syncFlavor = function()
    local mali = style.IsMali()
    for name, control in pairs(styleButtons) do
        style.SetButtonActive(control, (name == "mali") == mali)
    end
    for name, control in pairs(fontButtons) do
        style.SetButtonActive(control, mali and name == style.FontChoice())
        control:SetEnabled(mali)
    end
    for _, swatch in ipairs(swatches) do
        local color = style.Color(swatch.key)
        swatch.color:SetColorTexture(color[1], color[2], color[3], 1)
        swatch:SetAlpha(mali and 1 or 0.35)
        swatch.label:SetAlpha(mali and 1 or 0.35)
    end
    restoreColors:SetEnabled(mali)
    colorNote:SetText(mali and "Click a swatch to change it. Changes show right away and are saved."
        or "These apply to Mali Style. Switch to Mali Style to edit them.")
end
flavor:SetScript("OnShow", function()
    syncFlavor()
end)

style.OnApply(function()
    applyOpacity()
    refresh()
end)

-- Mali Style Layout

do
local ui = {}
local function maliWidget(widget)
    maliOnly[#maliOnly + 1] = widget
    return widget
end

local function maliText(parent, size, weight, template)
    return maliWidget(style.Font(parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight"), size, weight))
end

local function maliLine(parent, y)
    local line = maliWidget(parent:CreateTexture(nil, "ARTWORK"))
    line:SetPoint("TOPLEFT", 1, y)
    line:SetPoint("TOPRIGHT", -1, y)
    line:SetHeight(1)
    return line
end

local MALI_HEIGHT, CLASSIC_HEIGHT = 724, 700
ui.dividers = { maliLine(f, -36), maliLine(f, -98) }
ui.bottomLine = maliWidget(f:CreateTexture(nil, "ARTWORK"))
ui.bottomLine:SetPoint("BOTTOMLEFT", 1, 52)
ui.bottomLine:SetPoint("BOTTOMRIGHT", -1, 52)
ui.bottomLine:SetHeight(1)
ui.dividers[#ui.dividers + 1] = ui.bottomLine

-- Header: title (already made with the panel), compact and close icons.
ui.headerClose = maliWidget(style.IconButton(f, "close", 22, 14))
ui.headerClose:SetPoint("TOPRIGHT", -8, -7)
ui.headerClose:SetScript("OnClick", function()
    f:Hide()
end)
ui.headerCompact = maliWidget(style.IconButton(f, "compact", 22, 14))
ui.headerCompact:SetPoint("RIGHT", ui.headerClose, "LEFT", -4, 0)
ui.headerCompact:SetScript("OnClick", function()
    setCompact(true)
end)
for _, control in ipairs({ { ui.headerCompact, "Compact player" }, { ui.headerClose, "Close" } }) do
    control[1]:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(control[2])
        GameTooltip:Show()
    end)
    control[1]:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Now playing: ui.badge, place path, title, elapsed / progress / total.
ui.badge = maliWidget(CreateFrame("Frame", nil, f))
ui.badge:SetPoint("TOPLEFT", 14, -46)
ui.badge:SetSize(42, 42)
ui.badgeEdges = {}
for _, sides in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = ui.badge:CreateTexture(nil, "BORDER")
    edge:SetPoint(sides[1])
    edge:SetPoint(sides[2])
    if #ui.badgeEdges < 2 then edge:SetHeight(1) else edge:SetWidth(1) end
    ui.badgeEdges[#ui.badgeEdges + 1] = edge
end
ui.badgeIcon = ui.badge:CreateTexture(nil, "ARTWORK")
ui.badgeIcon:SetPoint("CENTER")
ui.badgeIcon:SetSize(22, 22)
ui.badgeIcon:SetTexture(style.MEDIA .. "icons\\music")

ui.nowPath = maliText(f, 11)
ui.nowPath:SetPoint("TOPLEFT", 68, -46)
ui.nowPath:SetPoint("RIGHT", -16, 0)
ui.nowPath:SetJustifyH("LEFT")
ui.nowPath:SetWordWrap(false)
ui.nowTitle = maliText(f, 15, "medium")
ui.nowTitle:SetPoint("TOPLEFT", 68, -61)
ui.nowTitle:SetPoint("RIGHT", -16, 0)
ui.nowTitle:SetJustifyH("LEFT")
ui.nowTitle:SetWordWrap(false)
ui.nowElapsed = maliText(f, 11)
ui.nowElapsed:SetPoint("TOPLEFT", 68, -81)
ui.nowElapsed:SetWidth(44)
ui.nowElapsed:SetJustifyH("LEFT")
ui.nowTotal = maliText(f, 11)
ui.nowTotal:SetPoint("TOPRIGHT", -16, -81)
ui.nowTotal:SetWidth(52)
ui.nowTotal:SetJustifyH("RIGHT")
ui.nowBar = maliWidget(CreateFrame("StatusBar", nil, f))
ui.nowBar:SetPoint("LEFT", ui.nowElapsed, "RIGHT", 4, 0)
ui.nowBar:SetPoint("RIGHT", ui.nowTotal, "LEFT", -6, 0)
ui.nowBar:SetHeight(3)
ui.nowBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
ui.nowBar:SetMinMaxValues(0, 1)
ui.nowBarBack = ui.nowBar:CreateTexture(nil, "BACKGROUND")
ui.nowBarBack:SetAllPoints()

-- Transport bar.
ui.barPrevious = maliWidget(style.IconButton(f, "prev", 30, 16))
ui.barPrevious:SetPoint("BOTTOMLEFT", 14, 11)
ui.barPrevious:SetScript("OnClick", function()
    advance(-1, false)
end)
ui.barPlay = maliWidget(style.IconButton(f, "play", 36, 18))
ui.barPlay.mmpEmphasis = true
ui.barPlay:SetPoint("LEFT", ui.barPrevious, "RIGHT", 4, 0)
ui.barPlay:SetScript("OnClick", function()
    if playing then
        stop()
    else
        playSelected()
    end
end)
ui.barNext = maliWidget(style.IconButton(f, "next", 30, 16))
ui.barNext:SetPoint("LEFT", ui.barPlay, "RIGHT", 4, 0)
ui.barNext:SetScript("OnClick", function()
    advance(1, false)
end)
ui.shuffleToggle = maliWidget(style.Toggle(f, "shuffle", "Shuffle", 82))
ui.shuffleToggle:SetPoint("LEFT", ui.barNext, "RIGHT", 14, 0)
ui.shuffleToggle:SetScript("OnClick", function()
    togglePlaybackSetting("shuffle", "mali bar")
end)
ui.repeatToggle = maliWidget(style.Toggle(f, "repeat", "Repeat", 80))
ui.repeatToggle:SetPoint("LEFT", ui.shuffleToggle, "RIGHT", 6, 0)
ui.repeatToggle:SetScript("OnClick", function()
    togglePlaybackSetting("repeatTrack", "mali bar")
end)

-- Volume: ui.speaker mutes / unmutes music; ui.slim slider sets music volume.
ui.speaker = maliWidget(style.IconButton(f, "volume", 26, 16))
ui.speaker:SetPoint("BOTTOMRIGHT", -204, 13)
ui.speaker:SetScript("OnClick", function()
    SetCVar("Sound_EnableMusic", GetCVar("Sound_EnableMusic") == "1" and "0" or "1")
    syncMusicToggle()
end)
ui.speaker:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(GetCVar("Sound_EnableMusic") == "1" and "Turn music off" or "Music is off")
    if GetCVar("Sound_EnableMusic") ~= "1" then
        GameTooltip:AddLine("Click to turn WoW's music on. The player needs it to play anything.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
ui.speaker:HookScript("OnLeave", function()
    GameTooltip:Hide()
end)
ui.slim = maliWidget(CreateFrame("Slider", nil, f))
ui.slim:SetOrientation("HORIZONTAL")
ui.slim:SetPoint("LEFT", ui.speaker, "RIGHT", 6, 0)
ui.slim:SetSize(116, 16)
ui.slim:SetMinMaxValues(0, 100)
ui.slim:SetValueStep(1)
if ui.slim.SetObeyStepOnDrag then
    ui.slim:SetObeyStepOnDrag(true)
end
ui.slim:EnableMouseWheel(true)
ui.slimTrack = ui.slim:CreateTexture(nil, "BACKGROUND")
ui.slimTrack:SetPoint("LEFT")
ui.slimTrack:SetPoint("RIGHT")
ui.slimTrack:SetHeight(3)
ui.slimThumb = ui.slim:CreateTexture(nil, "OVERLAY")
ui.slimThumb:SetSize(6, 12)
ui.slim:SetThumbTexture(ui.slimThumb)
ui.slimFill = ui.slim:CreateTexture(nil, "ARTWORK")
ui.slimFill:SetPoint("LEFT", ui.slimTrack, "LEFT")
ui.slimFill:SetPoint("RIGHT", ui.slimThumb, "CENTER")
ui.slimFill:SetHeight(3)
ui.slimText = maliText(f, 11)
ui.slimText:SetPoint("LEFT", ui.slim, "RIGHT", 8, 0)
ui.slimText:SetWidth(44)
ui.slimText:SetJustifyH("LEFT")
ui.slimSyncing = false
ui.slim:SetScript("OnValueChanged", function(_, value)
    if not ui.slimSyncing then
        setMusicVolumePercent(value)
    end
end)
ui.slim:SetScript("OnMouseWheel", function(_, delta)
    setMusicVolumePercent(math.floor(musicVolume() * 100 + 0.5) + delta)
end)

maliSyncVolume = function()
    ui.slimSyncing = true
    local actual = musicVolume() * 100
    ui.slim:SetValue(math.max(0, math.min(100, actual)))
    ui.slimText:SetText(actual > 0 and actual < 1 and "<1%" or (math.floor(actual + 0.5) .. "%"))
    ui.slimSyncing = false
end

-- Compact player (Mali): expand icon, previous / play-stop / next, progress line.
ui.compactExpand = maliWidget(style.IconButton(compact, "expand", 20, 12))
ui.compactExpand:SetPoint("TOPRIGHT", -5, -5)
ui.compactExpand:SetScript("OnClick", function()
    showTab("library")
    setCompact(false)
end)
hoverHandlers(ui.compactExpand, "Open full player")
ui.compactNext = maliWidget(style.IconButton(compact, "next", 22, 13))
ui.compactNext:SetPoint("BOTTOMRIGHT", -10, 7)
ui.compactNext:SetScript("OnClick", function()
    advance(1, false)
end)
hoverHandlers(ui.compactNext)
ui.compactPlay = maliWidget(style.IconButton(compact, "play", 22, 13))
ui.compactPlay:SetPoint("RIGHT", ui.compactNext, "LEFT", -2, 0)
ui.compactPlay:SetScript("OnClick", function()
    if playing then
        stop()
    else
        playSelected()
    end
end)
hoverHandlers(ui.compactPlay)
ui.compactPrevious = maliWidget(style.IconButton(compact, "prev", 22, 13))
ui.compactPrevious:SetPoint("RIGHT", ui.compactPlay, "LEFT", -2, 0)
ui.compactPrevious:SetScript("OnClick", function()
    advance(-1, false)
end)
hoverHandlers(ui.compactPrevious)
ui.compactLine = maliWidget(CreateFrame("StatusBar", nil, compact))
ui.compactLine:SetPoint("BOTTOMLEFT", 1, 1)
ui.compactLine:SetPoint("BOTTOMRIGHT", -1, 1)
ui.compactLine:SetHeight(2)
ui.compactLine:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
ui.compactLine:SetMinMaxValues(0, 1)

-- Resizing: the main window (Mali Style) and the compact player width (both styles).

if f.SetResizeBounds then
    f:SetResizeBounds(600, 520, 1400, 1400)
elseif f.SetMinResize then
    f:SetMinResize(600, 520)
    f:SetMaxResize(1400, 1400)
end
f:SetResizable(true)

local function makeGrip(parent, size)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(size, size)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetFrameLevel(parent:GetFrameLevel() + 20)
    return grip
end

ui.fullGrip = maliWidget(makeGrip(f, 16))
ui.fullGrip:SetScript("OnMouseDown", function(_, which)
    if which == "LeftButton" then
        f:StartSizing("BOTTOMRIGHT")
    end
end)
ui.fullGrip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    if db then
        db.fullSize = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
    end
    savePosition(f, "position")
end)

-- Settings, Flavor and Help scroll when the window is shorter than their content.
local function shiftContent(frame, dy, belowY)
    local objects = { frame:GetChildren() }
    for _, region in ipairs({ frame:GetRegions() }) do
        objects[#objects + 1] = region
    end
    for _, object in ipairs(objects) do
        local points, touched = {}, false
        for index = 1, object:GetNumPoints() do
            local point, relative, relativePoint, x, y = object:GetPoint(index)
            if (relative == nil or relative == frame) and (not belowY or y <= belowY) then
                y = y + dy
                touched = true
            end
            points[index] = { point, relative or frame, relativePoint, x, y }
        end
        if touched then
            object:ClearAllPoints()
            for _, saved in ipairs(points) do
                object:SetPoint(saved[1], saved[2], saved[3], saved[4], saved[5])
            end
        end
    end
end

-- The width slider is replaced by the compact player's own resize grip.
widthLabel:Hide()
widthSlider:Hide()
widthNote:Hide()
shiftContent(settings, 52, -365)

ui.views = {}
local function scrollTab(content, name, height)
    local view = CreateFrame("ScrollFrame", "MaliMusicPlayer" .. name .. "View", f, "UIPanelScrollFrameTemplate")
    view:SetPoint("TOPLEFT", 0, -138)
    view:SetPoint("BOTTOMRIGHT", -30, 40)
    view:Hide()
    content:SetParent(view)
    content:ClearAllPoints()
    content:SetSize(580, height)
    content:Show()
    view:SetScrollChild(content)
    shiftContent(content, 138)
    local bar = view.ScrollBar or _G[view:GetName() .. "ScrollBar"]
    view.scrollBarHideable = true
    view:HookScript("OnScrollRangeChanged", function(self, _, yRange)
        if bar then
            bar:SetShown((yRange or self:GetVerticalScrollRange() or 0) > 1)
        end
    end)
    style.ScrollBar(bar)
    content.view = view
    ui.views[#ui.views + 1] = { view = view, content = content }
end
scrollTab(settings, "Settings", 480)
scrollTab(flavor, "Flavor", 440)
scrollTab(help, "Help", 470)

layout = function()
    local mali = style.IsMali()
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 16, -178)
    scroll:SetPoint("BOTTOMRIGHT", -41, mali and 60 or 90)
    for _, entry in ipairs(ui.views) do
        entry.view:ClearAllPoints()
        entry.view:SetPoint("TOPLEFT", 0, -138)
        entry.view:SetPoint("BOTTOMRIGHT", -30, mali and 58 or 40)
        entry.content:SetWidth(math.max(560, (f:GetWidth() or 610) - 40))
    end
    local height = scroll:GetHeight() or 0
    visibleRows = height > ROW_HEIGHT and math.floor(height / ROW_HEIGHT) or VISIBLE_ROWS
    refresh()
end
f:HookScript("OnSizeChanged", function()
    layout()
end)

compact:SetResizable(true)
if compact.SetResizeBounds then
    compact:SetResizeBounds(180, 56, 400, 56)
elseif compact.SetMinResize then
    compact:SetMinResize(180, 56)
    compact:SetMaxResize(400, 56)
end
ui.compactGrip = makeGrip(compact, 10)
ui.compactGrip:SetAlpha(0.6)
ui.compactGrip:SetScript("OnMouseDown", function(_, which)
    if which == "LeftButton" then
        compact:StartSizing("BOTTOMRIGHT")
    end
end)
ui.compactGrip:SetScript("OnMouseUp", function()
    compact:StopMovingOrSizing()
    compact:SetHeight(56)
    if db then
        db.compactWidth = compactWidth(compact:GetWidth())
    end
    applyCompactWidth(compact:GetWidth())
    savePosition(compact, "compactPosition")
end)
ui.sizingCompact = false
compact:HookScript("OnSizeChanged", function(self, width)
    if ui.sizingCompact then
        return
    end
    ui.sizingCompact = true
    titleViewport:SetWidth(width - 48)
    compactTime:SetWidth(width - 120)
    resetMarquee()
    ui.sizingCompact = false
end)

maliUpdate = function()
    if not style.IsMali() then
        return
    end
    local track = current and tracks[current] or tracks[selected]
    local place = track and track.place
    local path
    if playbackStatus then
        path = "|cffff8080" .. safe(playbackStatus) .. "|r"
    elseif place then
        path = safe(place.category.name .. "  \226\128\186  " .. place.name)
    elseif track then
        path = track.artist and track.artist ~= "" and safe(track.artist) or "Your library"
    else
        path = ""
    end
    if track and not playing then
        path = (current and "Stopped" or "Selected") .. (path ~= "" and "  \194\183  " .. path or "")
    end
    ui.nowPath:SetText(path)
    ui.nowTitle:SetText(track and safe(track.title or label(track)) or "Pick something to play")
    local duration = playing and track and gameMonitor.duration(track) or 0
    local elapsed = playing and math.max(0, GetTime() - started) or 0
    ui.nowElapsed:SetText(clock(elapsed))
    ui.nowTotal:SetText(duration > 0 and clock(duration) or "--:--")
    local fraction = duration > 0 and math.min(1, elapsed / duration) or 0
    ui.nowBar:SetValue(fraction)
    ui.compactLine:SetValue(fraction)
    ui.compactLine:SetShown(playing and duration > 0)
    local icon = playing and "stop" or "play"
    ui.barPlay:SetIcon(icon)
    ui.compactPlay:SetIcon(icon)
    ui.shuffleToggle:SetOn(db and db.shuffle)
    ui.repeatToggle:SetOn(db and db.repeatTrack)
    local gameWithoutEnd = current and sourceOf(current) == "game" and not gameMonitor.status
    ui.shuffleToggle:SetEnabled(not gameWithoutEnd)
    ui.repeatToggle:SetEnabled(not gameWithoutEnd)
    local musicOn = GetCVar("Sound_EnableMusic") == "1" and musicVolume() > 0
    ui.speaker:SetIcon(musicOn and "volume" or "mute")
    ui.speaker.mmpDanger = not musicOn
    style.IconRefresh(ui.speaker)
end

style.OnApply(function(mali)
    for _, widget in ipairs(classicOnly) do
        widget:SetShown(not mali)
    end
    for _, widget in ipairs(maliOnly) do
        widget:SetShown(mali)
    end
    if mali then
        local size = db and type(db.fullSize) == "table" and db.fullSize
        f:SetSize(size and size[1] or 610, size and size[2] or MALI_HEIGHT)
    else
        f:SetSize(610, CLASSIC_HEIGHT)
    end
    layout()
    local accent, border, background = style.Color("accent"), style.Color("border"), style.Color("background")
    for _, line in ipairs(ui.dividers) do
        line:SetColorTexture(border[1], border[2], border[3], 0.6)
    end
    for _, edge in ipairs(ui.badgeEdges) do
        edge:SetColorTexture(border[1], border[2], border[3], 1)
    end
    ui.badgeIcon:SetVertexColor(accent[1], accent[2], accent[3])
    ui.nowPath:SetTextColor(0.6, 0.58, 0.64)
    ui.nowTitle:SetTextColor(1, 1, 1)
    ui.nowElapsed:SetTextColor(accent[1], accent[2], accent[3])
    ui.nowTotal:SetTextColor(0.6, 0.58, 0.64)
    ui.nowBar:SetStatusBarColor(accent[1], accent[2], accent[3])
    ui.nowBarBack:SetColorTexture(background[1] * 2.2, background[2] * 2.1, background[3] * 2.4, 1)
    ui.slimTrack:SetColorTexture(background[1] * 2.2, background[2] * 2.1, background[3] * 2.4, 1)
    ui.slimFill:SetColorTexture(accent[1], accent[2], accent[3], 1)
    ui.slimThumb:SetColorTexture(0.9, 0.88, 0.84, 1)
    ui.slimText:SetTextColor(0.66, 0.64, 0.7)
    ui.compactLine:SetStatusBarColor(accent[1], accent[2], accent[3])
    if mali then
        compactTime:SetTextColor(accent[1], accent[2], accent[3])
    else
        compactTime:SetTextColor(1, 0.82, 0)
    end
    resetMarquee()
    if currentTab then
        showTab(currentTab)
    end
    maliSyncVolume()
    maliUpdate()
end)
end

-- Compact Quick Controls

local menu = CreateFrame("Frame", "MaliMusicPlayerQuickControls", compact)
menu:SetSize(244, 256)
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:Hide()
table.insert(UISpecialFrames, "MaliMusicPlayerQuickControls")
local menuBackground = menu:CreateTexture(nil, "BACKGROUND")
menuBackground:SetAllPoints()
menuBackground:SetColorTexture(0.025, 0.025, 0.035, 0.98)
font(menu, "GameFontNormal", 10, -10, 224):SetText("MaliMusicPlayer - Quick controls")
local menuTrack = font(menu, "GameFontHighlightSmall", 10, -32, 224)
menuTrack:SetWordWrap(false)

local function action(y, caption, callback)
    return button(menu, caption, 8, y, 228, function()
        menu:Hide()
        callback()
    end)
end

action(-55, "Play / restart current track", function()
    playSelected()
end)
action(-82, "Stop", stop)
action(-109, "Previous track", function()
    advance(-1, false)
end)
action(-136, "Next track", function()
    advance(1, false)
end)
menuShuffle = action(-163, "Shuffle: Off", function()
    togglePlaybackSetting("shuffle", "quick menu")
end)
menuRepeat = action(-190, "Repeat: Off", function()
    togglePlaybackSetting("repeatTrack", "quick menu")
end)
action(-217, "Open Settings / About", function()
    showTab("settings")
    setCompact(false)
end)

local function toggleMenu()
    if menu:IsShown() then
        menu:Hide()
        return
    end
    local index = current or selected
    menuTrack:SetText(tracks[index] and safe(label(tracks[index])) or "No track selected")
    sync()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 8, y / scale + 8)
    menu:Show()
    GameTooltip:Hide()
end

local away = 0
menu:SetScript("OnShow", function()
    away = 0
end)
menu:SetScript("OnUpdate", function(self, elapsed)
    if self:IsMouseOver() or compact:IsMouseOver() then
        away = 0
    else
        away = away + elapsed
        if away > 0.6 then
            self:Hide()
        end
    end
end)

-- Compact Mouse Input

local titlePressX, titlePressY
local titleDragged = false
local TITLE_DRAG_DISTANCE = 5

local function titleMoved()
    if not titlePressX then
        return false
    end
    local x, y = GetCursorPosition()
    local scale = compact:GetEffectiveScale()
    return ((x - titlePressX) / scale) ^ 2 + ((y - titlePressY) / scale) ^ 2
        >= TITLE_DRAG_DISTANCE ^ 2
end

local function clearTitlePress()
    titlePressX, titlePressY = nil, nil
    titleDragged = false
end

local function compactMouseDown(self, which)
    if which ~= "LeftButton" then
        return
    end
    menu:Hide()
    hideTitleTooltip()
    GameTooltip:Hide()
    if self == titleViewport then
        titlePressX, titlePressY = GetCursorPosition()
        titleDragged = false
    elseif not compactMoving then
        compactMoving = true
        compact:StartMoving()
    end
end

local function compactMouseUp(self, which)
    if which == "LeftButton" then
        local openFull = self == titleViewport and titlePressX
            and not titleDragged and not titleMoved()
        clearTitlePress()
        finishCompactMove()
        if openFull then
            showTab("library")
            setCompact(false)
        end
    elseif which == "RightButton" and not compactMoving then
        clearTitlePress()
        toggleMenu()
    end
end

compact:HookScript("OnUpdate", function()
    if not titlePressX then
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        clearTitlePress()
        finishCompactMove()
    elseif not titleDragged and titleMoved() then
        titleDragged = true
        compactMoving = true
        compact:StartMoving()
    end
end)

for _, surface in ipairs({ compact, titleViewport }) do
    surface:SetScript("OnMouseDown", compactMouseDown)
    surface:SetScript("OnMouseUp", compactMouseUp)
end
compact:HookScript("OnHide", function()
    clearTitlePress()
    finishCompactMove()
    menu:Hide()
    hideTitleTooltip()
    GameTooltip:Hide()
end)

-- Minimap Library Integration

local minimapButton
local minimapBroker
local minimapRetryFrame
local MINIMAP_LAUNCHER = "MaliMusicPlayer"

local function openFromMinimap(which)
    if which == "RightButton" then
        setCompact(true)
    elseif which == "LeftButton" then
        showTab("library")
        setCompact(false)
    end
end

local function createStandardMinimapButton()
    local stub = _G.LibStub
    if not stub then
        return false
    end
    local icon = stub:GetLibrary("LibDBIcon-1.0", true)
    local broker = stub:GetLibrary("LibDataBroker-1.1", true)
    if not icon or not broker or not db then
        return false
    end
    if type(db.minimap) ~= "table" then
        db.minimap = {}
    end
    if tonumber(db.minimap.minimapPos) == nil then
        db.minimap.minimapPos = tonumber(db.minimapAngle) or 225
    end
    if db.minimap.hide == nil then
        db.minimap.hide = false
    end
    local object = broker:GetDataObjectByName(MINIMAP_LAUNCHER)
    if not object then
        object = broker:NewDataObject(MINIMAP_LAUNCHER, {
            type = "launcher",
            text = "MaliMusicPlayer",
            icon = style.MEDIA .. "icon",
            OnClick = function(_, which)
                openFromMinimap(which)
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("MaliMusicPlayer")
                if current and tracks[current] then
                    tooltip:AddLine((playing and "Playing: " or "Stopped: ") .. safe(label(tracks[current])),
                        1, 1, 1, true)
                end
                tooltip:AddLine("Left-click: open full player", 0.75, 0.85, 1)
                tooltip:AddLine("Right-click: open compact player", 0.75, 0.85, 1)
                tooltip:AddLine("Drag to reposition", 0.75, 0.85, 1)
            end,
        })
    end
    minimapBroker = object
    if not icon:IsRegistered(MINIMAP_LAUNCHER) then
        icon:Register(MINIMAP_LAUNCHER, object, db.minimap)
    else
        icon:Refresh(MINIMAP_LAUNCHER, db.minimap)
    end
    local standard = icon:GetMinimapButton(MINIMAP_LAUNCHER)
    if not standard then
        return false
    end
    local old = minimapButton
    if old and old ~= standard then
        old:SetScript("OnUpdate", nil)
        old:EnableMouse(false)
        old:Hide()
        old:SetParent(nil)
        old:ClearAllPoints()
    end
    minimapButton = standard
    if minimapRetryFrame then
        minimapRetryFrame:UnregisterAllEvents()
    end
    trace(VERSION .. " minimap: LibDBIcon active; launcher registered.")
    return true
end

-- Minimap Fallback

local function createFallbackMinimapButton()
    if minimapButton or not Minimap then
        return
    end
    local control = CreateFrame("Button", "MaliMusicPlayerMinimapButton", Minimap)
    minimapButton = control
    control:SetSize(32, 32)
    control:SetFrameStrata("MEDIUM")
    control:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    control:EnableMouse(true)
    control:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    control:RegisterForDrag("LeftButton")
    local icon = control:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture(style.MEDIA .. "icon")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = control:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    control:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight", "ADD")
    local saved = db and type(db.minimap) == "table" and db.minimap.minimapPos
    local angle = tonumber(saved) or tonumber(db and db.minimapAngle) or 225
    local dragging, wasDragged = false, false

    local function position()
        if minimapButton ~= control then
            return
        end
        local radians = math.rad(angle)
        local radiusX = Minimap:GetWidth() / 2 + 8
        local radiusY = Minimap:GetHeight() / 2 + 8
        control:ClearAllPoints()
        control:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radiusX, math.sin(radians) * radiusY)
    end

    local function cursorAngle()
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        if not centerX or not centerY then
            return
        end
        local deltaX, deltaY = x / scale - centerX, y / scale - centerY
        if deltaX == 0 and deltaY == 0 then
            return
        end
        local radians
        if deltaX == 0 then
            radians = deltaY > 0 and math.pi / 2 or -math.pi / 2
        else
            radians = math.atan(deltaY / deltaX)
            if deltaX < 0 then
                radians = radians + math.pi
            end
        end
        angle = math.deg(radians) % 360
        position()
    end

    local function finishDrag()
        if not dragging then
            return
        end
        dragging = false
        if db then
            db.minimapAngle = angle
            if type(db.minimap) ~= "table" then
                db.minimap = {}
            end
            db.minimap.minimapPos = angle
        end
    end

    control:SetScript("OnMouseDown", function(self, which)
        if which == "LeftButton" then
            wasDragged = false
        end
    end)
    control:SetScript("OnDragStart", function()
        dragging = true
        wasDragged = true
        GameTooltip:Hide()
        cursorAngle()
    end)
    control:SetScript("OnDragStop", finishDrag)
    control:SetScript("OnMouseUp", function(self, which)
        if which == "LeftButton" then
            finishDrag()
        end
    end)
    control:SetScript("OnUpdate", function()
        if dragging then
            cursorAngle()
            if not IsMouseButtonDown("LeftButton") then
                finishDrag()
            end
        end
    end)
    control:SetScript("OnClick", function(self, which)
        if which == "RightButton" or not wasDragged then
            openFromMinimap(which)
        end
        wasDragged = false
    end)
    control:SetScript("OnEnter", function(self)
        if dragging then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("MaliMusicPlayer")
        if current and tracks[current] then
            GameTooltip:AddLine((playing and "Playing: " or "Stopped: ") .. safe(label(tracks[current])),
                1, 1, 1, true)
        end
        GameTooltip:AddLine("Left-click: open full player", 0.75, 0.85, 1)
        GameTooltip:AddLine("Right-click: open compact player", 0.75, 0.85, 1)
        GameTooltip:AddLine("Drag to reposition", 0.75, 0.85, 1)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    control:SetScript("OnHide", function()
        finishDrag()
        GameTooltip:Hide()
    end)
    Minimap:HookScript("OnSizeChanged", position)
    position()
    control:SetShown(not (db and type(db.minimap) == "table" and db.minimap.hide))
    trace(VERSION .. " minimap: custom fallback; LibDBIcon/LibDataBroker not loaded.")
end

local function createMinimapButton()
    if minimapButton or minimapRetryFrame then
        return
    end
    minimapRetryFrame = CreateFrame("Frame")
    minimapRetryFrame:RegisterEvent("ADDON_LOADED")
    minimapRetryFrame:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            createStandardMinimapButton()
        end)
    end)
    C_Timer.After(0, function()
        if not createStandardMinimapButton() then
            createFallbackMinimapButton()
        end
    end)
end

-- Game Options Registration

local function openPlayerSettings()
    if SettingsPanel and SettingsPanel:IsShown() then
        SettingsPanel:Hide()
    end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
        InterfaceOptionsFrame:Hide()
    end
    if GameMenuFrame and GameMenuFrame:IsShown() then
        GameMenuFrame:Hide()
    end
    showTab("settings")
    setCompact(false)
end

local optionsRegistered = false

local function registerOptionsPanel()
    if optionsRegistered then
        return
    end
    local panel = CreateFrame("Frame", "MaliMusicPlayerOptionsPanel", UIParent)
    panel.name = "MaliMusicPlayer"
    panel:Hide()
    font(panel, "GameFontNormalLarge", 20, -20, 540):SetText("MaliMusicPlayer")
    font(panel, "GameFontHighlight", 20, -55, 540):SetText("Your music, in-game.")
    font(panel, "GameFontHighlightSmall", 20, -86, 540):SetText(
        "Open the player to manage your library, playback, and appearance settings."
    )
    button(panel, "Open Player Settings", 20, -135, 190, openPlayerSettings)
    font(panel, "GameFontDisableSmall", 20, -178, 540):SetText("Prefer a shortcut? Type /mmp to open the player.")
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "MaliMusicPlayer")
        Settings.RegisterAddOnCategory(category)
        optionsRegistered = true
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        optionsRegistered = true
    else
        say("Blizzard's AddOns settings registration is unavailable. /mmp still works.")
    end
end

-- Events and Saved Settings

local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "LOADING_SCREEN_ENABLED",
    "LOADING_SCREEN_DISABLED",
    "CVAR_UPDATE",
    "PLAYER_LOGOUT",
}) do
    events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "MaliMusicPlayer" then
        MaliMusicPlayerDB = MaliMusicPlayerDB or {}
        db = MaliMusicPlayerDB
        style.Init(db)
        trace("Startup: repeat=" .. tostring(db.repeatTrack) .. " shuffle=" .. tostring(db.shuffle))
        if not db.backgroundAudioDefault085 then
            db.backgroundAudioDefault085 = true
            SetCVar("Sound_EnableSoundWhenGameIsInBG", "1")
        end
        if db.compactOnClose == nil then
            db.compactOnClose = true
        end
        compactOnCloseCheck:SetChecked(db.compactOnClose and true or false)
        syncBackgroundAudio()
        db.compactBackground = opacity(db.compactBackground, 0, 0.85)
        db.compactTextOpacity = opacity(db.compactTextOpacity, 0.2, 0.85)
        db.compactButtonOpacity = opacity(db.compactButtonOpacity, 0.2, 0.75)
        db.fullPlayerOpacity = opacity(db.fullPlayerOpacity, 0.33, 1)
        local mode = db.compactScrollMode
        if mode ~= "loop" and mode ~= "bounce" and mode ~= "static" then
            db.compactScrollMode = "loop"
        end
        db.compactDefaults077 = true
        if db.compactTitleTooltip == nil then
            db.compactTitleTooltip = true
        end
        if db.compactElapsedOnly == nil then
            db.compactElapsedOnly = false
        end
        titleTooltipCheck:SetChecked(db.compactTitleTooltip and true or false)
        elapsedOnlyCheck:SetChecked(db.compactElapsedOnly and true or false)
        restoreSelection()
        db.compactWidth = compactWidth(db.compactWidth)
        syncScrollMode()
        restorePosition(f, "position")
        restorePosition(compact, "compactPosition")
        applyCompactWidth(db.compactWidth)
        sync()
        rebuild()
        syncVolume()
        syncMusicToggle()
        opacityInitializing = true
        backgroundSlider:SetValue(db.compactBackground * 100)
        textSlider:SetValue(db.compactTextOpacity * 100)
        buttonSlider:SetValue(db.compactButtonOpacity * 100)
        widthSlider:SetValue(db.compactWidth)
        widthLabel:SetText("Compact width: " .. db.compactWidth .. " px")
        fullOpacitySlider:SetValue(db.fullPlayerOpacity * 100)
        fullOpacityLabel:SetText("Full player opacity: " .. math.floor(db.fullPlayerOpacity * 100 + 0.5) .. "%")
        f:SetAlpha(db.fullPlayerOpacity)
        opacityInitializing = false
        style.Apply()
        if type(db.gameDurations70959) == "table" then
            db.gameDurations = db.gameDurations or {}
            for id, seconds in pairs(db.gameDurations70959) do
                db.gameDurations[id] = db.gameDurations[id] or seconds
            end
            db.gameDurations70959 = nil
        end
        local gameText = #gamePlaces > 0 and (", " .. (#tracks - mp3Count) .. " game music tracks in "
            .. #gamePlaces .. " places") or ""
        say("v" .. VERSION .. ": " .. mp3Count .. " library tracks" .. gameText .. ". /mmp to open.")
        local state = library.companionState()
        if state == "disabled" or state == "outdated" then
            say(library.musicHelp():gsub("\n\n", " "))
        end
    elseif event == "PLAYER_LOGIN" then
        registerOptionsPanel()
        createMinimapButton()
    elseif event == "LOADING_SCREEN_ENABLED" then
        loading = true
        gameMonitor.interrupted = true
    elseif event == "LOADING_SCREEN_DISABLED" then
        loading = false
        if playing then
            updateTime()
            C_Timer.After(1, function()
                if playing and not loading then
                    PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg")
                end
            end)
        end
    elseif event == "CVAR_UPDATE" then
        syncBackgroundAudio()
        syncMusicToggle()
        if f:IsShown() then
            syncVolume()
        end
        for _, control in ipairs(compactButtons) do
            if control.hovered and GameTooltip:GetOwner() == control then
                showCompactButtonTooltip(control, control.tooltipCaption)
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        playing = false
        stopHandle()
        StopMusic()
    end
end)

-- Playback Updates

local tick = 0
events:SetScript("OnUpdate", function(self, elapsed)
    if not playing or loading then
        return
    end
    tick = tick + elapsed
    if tick < 0.2 then
        return
    end
    tick = 0
    local blocked = audioBlock()
    if blocked then
        playbackFailure(current, nil, blocked)
        return
    end
    updateTime()
    local track = tracks[current]
    if track.fileDataID then
        if not gameMonitor.status or not soundHandle then
            return
        end
        if gameMonitor.status(soundHandle) then
            gameMonitor.seen = true
        elseif gameMonitor.seen or GetTime() - started > 3 then
            if gameMonitor.seen then
                -- Remember the length, unless a loading screen cut into this play.
                local observed = GetTime() - started
                if not gameMonitor.interrupted then
                    db.gameDurations = db.gameDurations or {}
                    db.gameDurations[track.fileDataID] = observed
                end
                trace(string.format("Game finish: id=%d observed=%.2fs clean=%s", track.fileDataID, observed,
                    tostring(not gameMonitor.interrupted)))
                advance(1, true)
            else
                trace("Game track never reported playing")
                playbackFailure(current, nil, "Playback failed")
            end
        end
        return
    end
    local duration = track.duration or 0
    if duration > 0 and GetTime() - started >= duration + 0.4 then
        advance(1, true)
    end
end)

-- Slash Commands

SLASH_MALIMUSICPLAYER1 = "/malimusicplayer"
SLASH_MALIMUSICPLAYER2 = "/mmp"
SLASH_MALIMUSICPLAYER3 = "/musicplayer"
SLASH_MALIMUSICPLAYER4 = "/malimusic"
SlashCmdList.MALIMUSICPLAYER = function(message)
    message = string.lower(strtrim(message or ""))
    if message == "compact" then
        setCompact(true)
    elseif message == "full" then
        showTab("library")
        setCompact(false)
    elseif message == "stop" then
        stop()
    elseif message == "next" then
        advance(1, false)
    elseif message == "prev" then
        advance(-1, false)
    elseif message == "play" then
        playSelected()
    elseif message == "game" then
        showTab("game")
        setCompact(false)
    else
        togglePlayer()
    end
end

-- Diagnostics

SLASH_MALIMUSICPLAYERDIAG1 = "/mmpdiag"
SlashCmdList.MALIMUSICPLAYERDIAG = function(message)
    message = string.lower(strtrim(message or ""))
    if message == "on" then
        diagnostics = true
        say("Audio diagnostics enabled for this session.")
    elseif message == "off" then
        diagnostics = false
        say("Audio diagnostics disabled.")
    elseif message == "dump" then
        for _, entry in ipairs(diagnosticLog) do
            say("[audio] " .. entry)
        end
        return
    elseif message ~= "status" and message ~= "" then
        say("/mmpdiag on | off | status | dump")
        return
    end
    local source = sourceOf(current or selected or 1)
    local history = histories[source]
    local place = tracks[current or selected or 0] and tracks[current or selected].place
    say("[audio] place=" .. (place and place.key or "-") .. " catalog=" .. tostring(catalog and catalog.build)
        .. " places=" .. #gamePlaces .. " isPlayingAPI=" .. tostring(gameMonitor.status ~= nil))
    say("[audio] source=" .. source .. " history=" .. history.position .. "/" .. #history
        .. " repeat=" .. tostring(db and db.repeatTrack) .. " shuffle=" .. tostring(db and db.shuffle)
        .. " retry=" .. tostring(retryTrack))
    say("[audio] volume=" .. musicVolume() .. " playing=" .. tostring(playing)
        .. " handle=" .. tostring(soundHandle) .. " track=" .. tostring(current)
        .. " selected=" .. tostring(selected) .. " allSound=" .. tostring(GetCVar("Sound_EnableAllSound"))
        .. " musicEnabled=" .. tostring(GetCVar("Sound_EnableMusic")))
end