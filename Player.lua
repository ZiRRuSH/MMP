-- MaliMusicPlayer 0.9a

-- State

local tracks = {}
for _, track in ipairs(MaliMusicPlayerLibrary or {}) do
    tracks[#tracks + 1] = track
end
local mp3Count = #tracks
local _, clientBuild = GetBuildInfo()
local gameCatalog = MaliMusicPlayerGameMusic
if gameCatalog and tostring(clientBuild) == gameCatalog.build then
    for _, track in ipairs(gameCatalog.tracks) do
        tracks[#tracks + 1] = track
    end
end
local browseGame = false
local gameMonitor = { status = C_Sound and C_Sound.IsPlaying }
function gameMonitor.duration(track)
    local samples = MaliMusicPlayerDB and MaliMusicPlayerDB.gameDurations70959
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
    if db and tracks[index].path then
        db.selectedTrackPath = tracks[index].path
    end
end

local function restoreSelection()
    selected = 1
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
    return control
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
f.TitleText:SetText("MaliMusicPlayer 0.9a")
f:Hide()
table.insert(UISpecialFrames, "MaliMusicPlayerFrame")

local now = font(f, "GameFontHighlight", 16, -38, 575)
local timing = font(f, "GameFontNormalSmall", 16, -64, 575)
timing:SetText("Stopped")

local progress = CreateFrame("StatusBar", nil, f)
progress:SetPoint("TOPLEFT", 18, -87)
progress:SetSize(572, 7)
progress:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
progress:SetStatusBarColor(0.25, 0.7, 1)
progress:SetMinMaxValues(0, 1)
progress:SetValue(0)

local progressBackground = progress:CreateTexture(nil, "BACKGROUND")
progressBackground:SetAllPoints()
progressBackground:SetColorTexture(0.1, 0.1, 0.1, 1)

local library = CreateFrame("Frame", nil, f)
library:SetAllPoints()
local settings = CreateFrame("Frame", nil, f)
settings:SetAllPoints()
settings:Hide()
local help = CreateFrame("Frame", nil, f)
help:SetAllPoints()
help:Hide()

-- Tabs

local tabs = {}

local function makeTab(index, key, caption, width)
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(width, 32)
    tab:SetFrameLevel(math.max(library:GetFrameLevel(), settings:GetFrameLevel()) + 5)
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
    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 8, -4)
    highlight:SetPoint("BOTTOMRIGHT", -8, 5)
    highlight:SetColorTexture(1, 1, 1, 0.08)
    tab:SetScript("OnClick", function()
        showTab(key)
    end)
    tab.key = key
    tabs[index] = tab
end

makeTab(1, "library", "Library", 104)
makeTab(2, "game", "Game Music", 130)
makeTab(3, "settings", "Settings / About", 160)
makeTab(4, "help", "Help", 90)

showTab = function(which)
    local showLibrary = which == "library" or which == "game"
    library:SetShown(showLibrary)
    if showLibrary then
        browseGame = which == "game"
        if rebuild then
            rebuild()
        end
    end
    settings:SetShown(which == "settings")
    help:SetShown(which == "help")
    for _, tab in ipairs(tabs) do
        local active = tab.key == which
        local prefix = active and "Interface/PaperDollInfoFrame/UI-Character-ActiveTab-"
            or "Interface/PaperDollInfoFrame/UI-Character-InActiveTab-"
        tab.left:SetTexture(prefix .. "Left")
        tab.middle:SetTexture(prefix .. "Middle")
        tab.right:SetTexture(prefix .. "Right")
        tab.caption:SetTextColor(active and 1 or 0.85, active and 0.82 or 0.85, active and 0 or 0.85)
        tab.caption:ClearAllPoints()
        tab.caption:SetPoint("CENTER", 0, active and 2 or -1)
        tab:Show()
    end
end

-- Library Controls

local search = CreateFrame("EditBox", nil, library, "InputBoxTemplate")
search:SetPoint("TOPLEFT", 23, -142)
search:SetSize(435, 24)
search:SetAutoFocus(false)
search:SetMaxLetters(150)
search:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
search:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)

local resultCount = font(library, "GameFontNormalSmall", 477, -149, 110)
resultCount:SetText("0 tracks")

local scroll = CreateFrame("ScrollFrame", "MaliMusicPlayerScroll", library, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -178)
scroll:SetSize(553, VISIBLE_ROWS * ROW_HEIGHT)

for index = 1, VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, library)
    row:SetPoint("TOPLEFT", 16, -178 - (index - 1) * ROW_HEIGHT)
    row:SetSize(550, ROW_HEIGHT)
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetPoint("LEFT", 4, 0)
    row.title:SetWidth(470)
    row.title:SetJustifyH("LEFT")
    row.duration = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.duration:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self)
        if self.track then
            play(self.track, nil, true)
        end
    end)
    rows[index] = row
end

-- Compact Player

local compact = CreateFrame("Frame", "MaliMusicPlayerCompact", UIParent)
compact:SetSize(210, 56)
compact:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
compact:SetMovable(true)
compact:EnableMouse(true)
compact:SetClampedToScreen(true)
compact:Hide()

local compactBackground = compact:CreateTexture(nil, "BACKGROUND")
compactBackground:SetAllPoints()
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
        control:SetAlpha(control.hovered and 1 or opacity(db and db.compactButtonOpacity, 0.2, 0.30))
    end
    local textAlpha = hovered and 1 or opacity(db and db.compactTextOpacity, 0.2, 0.30)
    title:SetAlpha(textAlpha)
    titleRepeat:SetAlpha(textAlpha)
    compactTime:SetAlpha(textAlpha)
    compactBackground:SetColorTexture(0.025, 0.025, 0.025, opacity(db and db.compactBackground, 0, 0.30))
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
    control:SetScript("OnEnter", function(self)
        self.hovered = true
        applyOpacity()
        showCompactButtonTooltip(self, caption)
    end)
    control:SetScript("OnLeave", function(self)
        self.hovered = false
        applyOpacity()
        GameTooltip:Hide()
    end)
    control:SetScript("OnHide", function(self)
        self.hovered = false
        applyOpacity()
        GameTooltip:Hide()
    end)
    control:EnableMouseWheel(true)
    control:SetScript("OnMouseWheel", function(self, delta)
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
        if self.hovered then
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
        compactTime:SetText("Music disabled")
        return
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
end

refresh = function()
    FauxScrollFrame_Update(scroll, #filtered, VISIBLE_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for index, row in ipairs(rows) do
        local trackIndex = filtered[offset + index]
        row.track = trackIndex
        if trackIndex then
            local track = tracks[trackIndex]
            row.title:SetText((playing and current == trackIndex and "> " or "") .. safe(label(track)))
            row.duration:SetText(gameMonitor.duration(track) > 0 and clock(gameMonitor.duration(track)) or "--:--")
            row:Show()
        else
            row:Hide()
        end
    end
    if current then
        now:SetText((playing and "Playing: " or "Stopped: ") .. safe(label(tracks[current])))
    elseif tracks[selected] then
        now:SetText("Selected: " .. safe(label(tracks[selected])))
    else
        now:SetText("Select a song to play.")
    end
    local index = current or selected
    setTitle(tracks[index] and safe(label(tracks[index])) or "MaliMusicPlayer")
    updateCompactStatus()
end

rebuild = function()
    wipe(filtered)
    local query = string.lower(search:GetText() or "")
    local first = browseGame and (mp3Count + 1) or 1
    local last = browseGame and #tracks or mp3Count
    local total = last - first + 1
    for index = first, last do
        local track = tracks[index]
        if query == "" or string.find(string.lower(label(track)), query, 1, true) then
            filtered[#filtered + 1] = index
        end
    end
    if browseGame then
        table.sort(filtered, function(left, right)
            local leftName = string.lower(label(tracks[left]))
            local rightName = string.lower(label(tracks[right]))
            if leftName == rightName then
                return left < right
            end
            return leftName < rightName
        end)
    end
    if browseGame and total == 0 then
        resultCount:SetText("Build 70959 only")
    elseif query == "" then
        resultCount:SetText(total .. (browseGame and " candidates" or (total == 1 and " track" or " tracks")))
    else
        resultCount:SetText(#filtered .. " of " .. total)
    end
    FauxScrollFrame_SetOffset(scroll, 0)
    if scroll.ScrollBar then
        scroll.ScrollBar:SetValue(0)
    end
    refresh()
end

scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refresh)
end)
search:SetScript("OnTextChanged", rebuild)

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

local function playbackFailure(index, position, status)
    stop()
    retryTrack, retryPosition, playbackStatus = index, position, status
    timing:SetText(status .. ". Restore audio or check the track, then press Play to retry.")
    refresh()
    trace(status .. " track=" .. tostring(index))
    say(status .. ". Press Play to retry after checking the track and audio settings.")
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
    if source == "game" then
        if automatic then
            return play(outgoing, nil, true)
        end
        local position = history.position + direction
        if history[position] then
            return play(history[position], position, true)
        end
        return false
    end
    local first, count = 1, mp3Count
    local shuffle = db and db.shuffle
    local repeatTrack = db and db.repeatTrack
    local index, position, reason = outgoing, nil, "sequential"
    if automatic and repeatTrack then
        reason = "repeat"
    elseif direction < 0 and history.position > 1 then
        position = history.position - 1
        index, reason = history[position], "history-back"
    elseif direction > 0 and history.position < #history and not (automatic and shuffle) then
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

button(library, "Previous", 16, -619, 88, function()
    advance(-1, false)
end)
button(library, "Play", 110, -619, 70, function()
    playSelected()
end)
button(library, "Stop", 186, -619, 70, stop)
button(library, "Next", 262, -619, 70, function()
    advance(1, false)
end)
local shuffle = button(library, "Shuffle: Off", 338, -619, 120, function()
    togglePlaybackSetting("shuffle", "main")
end)
local repeatButton = button(library, "Repeat: Off", 464, -619, 130, function()
    togglePlaybackSetting("repeatTrack", "main")
end)

sync = function()
    local game = current and sourceOf(current) == "game"
    local shuffleText = db and db.shuffle and "Shuffle: On" or "Shuffle: Off"
    local repeatText = db and db.repeatTrack and "Repeat: On" or "Repeat: Off"
    if game then
        shuffleText = "Shuffle: N/A"
        repeatText = gameMonitor.status and "Loop: On" or "Loop: N/A"
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

local volumeLabel = font(f, "GameFontNormalSmall", 18, -668, 160)
local volume = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
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
        musicToggle:SetText(GetCVar("Sound_EnableMusic") == "1" and "Music: On" or "Music: Off")
    end
    updateCompactStatus()
end

musicToggle = button(f, "Music: Off", 400, -665, 94, function()
    local enabled = GetCVar("Sound_EnableMusic") == "1"
    SetCVar("Sound_EnableMusic", enabled and "0" or "1")
    syncMusicToggle()
end)
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

button(f, "Compact", 500, -665, 92, function()
    setCompact(true)
end)

local expandButton = iconButton(179, -4, "Interface/Buttons/UI-PlusButton-UP", "Open full player", function()
    showTab("library")
    setCompact(false)
end)
local playButton = iconButton(154, -29, "PLAY", "Play / restart current track", function()
    playSelected()
end)
local previousButton = iconButton(128, -29, "Interface/Buttons/UI-SpellbookIcon-PrevPage-Up", "Previous track", function()
    advance(-1, false)
end)
local stopButton = iconButton(154, -29, nil, "Stop playback", stop)
local nextButton = iconButton(180, -29, "Interface/Buttons/UI-SpellbookIcon-NextPage-Up", "Next track", function()
    advance(1, false)
end)

-- Compact Dimensions

local function compactWidth(value)
    return math.max(180, math.min(360, math.floor((tonumber(value) or 210) + 0.5)))
end

local function applyCompactWidth(value)
    local width = compactWidth(value)
    compact:SetWidth(width)
    titleViewport:SetWidth(width - 48)
    compactTime:SetWidth(width - 120)
    expandButton:ClearAllPoints()
    expandButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -8, -4)
    playButton:ClearAllPoints()
    playButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -33, -29)
    previousButton:ClearAllPoints()
    previousButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -85, -29)
    stopButton:ClearAllPoints()
    stopButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -59, -29)
    nextButton:ClearAllPoints()
    nextButton:SetPoint("TOPRIGHT", compact, "TOPRIGHT", -7, -29)
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
font(settings, "GameFontDisableSmall", 24, -363, 550):SetText(
    "180-360 px. Default: 210 px. Width updates immediately and is saved."
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
    local alpha = opacity(math.floor(value + 0.5) / 100, 0.33, 0.70)
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
    "MaliMusicPlayer v0.9a - By Mali Gnosis, for Mali Gnosis."
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
        .. "Put your music in:\n"
        .. "|cff70cfffInterface/AddOns/MaliMusicPlayer/mp3/|r\n\n"
        .. "|cffffd1002. Update your library|r\n"
        .. "Run |cff70cfffUpdateLibrary.cmd|r inside:\n"
        .. "|cff70cfffInterface/AddOns/MaliMusicPlayer/|r\n"
        .. "This builds |cff70cfffLibrary.lua|r, the addon's track list.\n\n"
        .. "|cffffd1003. Refresh the player|r\n"
        .. "Return to WoW and type |cff70cfff/reload|r."
)

local helpNote = font(help, "GameFontHighlight", 24, -184, 550)
helpNote:ClearAllPoints()
helpNote:SetPoint("TOPLEFT", helpSteps, "BOTTOMLEFT", 0, -24)
helpNote:SetFont(helpFont, 13, "")
helpNote:SetSpacing(4)
helpNote:SetWordWrap(true)
helpNote:SetText(
    "WoW cannot scan your music folder directly. Whenever you add, remove, or rename music, "
        .. "run |cff70cfffUpdateLibrary.cmd|r again, then type |cff70cfff/reload|r."
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
            icon = "Interface/ICONS/ClassIcon_Warlock",
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
    trace("0.9a minimap: LibDBIcon active; Warlock launcher registered.")
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
    icon:SetTexture("Interface/ICONS/ClassIcon_Warlock")
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
    trace("0.9a minimap: custom fallback; LibDBIcon/LibDataBroker not loaded.")
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
        trace("Startup: repeat=" .. tostring(db.repeatTrack) .. " shuffle=" .. tostring(db.shuffle))
        if not db.backgroundAudioDefault085 then
            db.backgroundAudioDefault085 = true
            SetCVar("Sound_EnableSoundWhenGameIsInBG", "1")
        end
        if db.compactOnClose == nil then
            db.compactOnClose = false
        end
        compactOnCloseCheck:SetChecked(db.compactOnClose and true or false)
        syncBackgroundAudio()
        db.compactBackground = opacity(db.compactBackground, 0, 0.30)
        db.compactTextOpacity = opacity(db.compactTextOpacity, 0.2, 0.30)
        db.compactButtonOpacity = opacity(db.compactButtonOpacity, 0.2, 0.30)
        db.fullPlayerOpacity = opacity(db.fullPlayerOpacity, 0.33, 0.70)
        local mode = db.compactScrollMode
        if mode ~= "loop" and mode ~= "bounce" and mode ~= "static" then
            db.compactScrollMode = "loop"
        end
        db.compactDefaults077 = true
        if db.compactTitleTooltip == nil then
            db.compactTitleTooltip = true
        end
        if db.compactElapsedOnly == nil then
            db.compactElapsedOnly = true
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
        applyOpacity()
        say("v0.9a: " .. mp3Count .. " library tracks, " .. (#tracks - mp3Count) .. " game music tracks.")
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
            if gameMonitor.seen and not gameMonitor.interrupted then
                local observed = GetTime() - started
                db.gameDurations70959 = db.gameDurations70959 or {}
                db.gameDurations70959[track.fileDataID] = observed
                trace(string.format("Game finish: id=%d observed=%.2fs; looping", track.fileDataID, observed))
                advance(1, true)
            else
                trace("Game playback stopped without a clean sample")
                stop()
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
    local source = sourceOf(current or selected)
    local history = histories[source]
    say("[audio] source=" .. source .. " history=" .. history.position .. "/" .. #history
        .. " repeat=" .. tostring(db and db.repeatTrack) .. " shuffle=" .. tostring(db and db.shuffle)
        .. " retry=" .. tostring(retryTrack))
    say("[audio] volume=" .. musicVolume() .. " playing=" .. tostring(playing)
        .. " handle=" .. tostring(soundHandle) .. " track=" .. tostring(current)
        .. " selected=" .. tostring(selected) .. " allSound=" .. tostring(GetCVar("Sound_EnableAllSound"))
        .. " musicEnabled=" .. tostring(GetCVar("Sound_EnableMusic")))
end