-- MaliMusicPlayer 0.8.3 - in-game test candidate
local tracks=MaliMusicPlayerLibrary or {}
local db,current,selected,started=nil,nil,1,0
local playing,loading,soundHandle=false,false,nil
local diagnostics=false
local refresh,play,advance,sync,setCompact,togglePlayer,showTab
local filtered,rows,compactButtons={},{},{}
local VISIBLE_ROWS,ROW_HEIGHT=14,24
local MIN_VOLUME_PERCENT=0.1
local function say(s) print("|cff70cfffMaliMusicPlayer:|r "..s) end
local function trace(s) if diagnostics then say("[audio] "..s) end end
local function safe(s) return (tostring(s or ""):gsub("|","||")) end
local function label(t) return (t.artist and t.artist~="" and t.artist.." - " or "")..(t.title or "Untitled") end
local function rememberSelection(index)
 if not tracks[index] then return end
 selected=index
 if db then db.selectedTrackPath=tracks[index].path end
end
local function restoreSelection()
 selected=1
 if db and type(db.selectedTrackPath)=="string" then
  for i,t in ipairs(tracks) do
   if t.path==db.selectedTrackPath then selected=i;break end
  end
 end
 if db then db.selectedTrackPath=tracks[selected] and tracks[selected].path or nil end
end
local function musicVolume() return math.max(0,math.min(1,tonumber(GetCVar("Sound_MusicVolume")) or 0)) end
local function sliderPercent(value)
 return math.max(MIN_VOLUME_PERCENT,math.min(100,math.floor((tonumber(value) or MIN_VOLUME_PERCENT)*10+0.5)/10))
end
local function percentText(value) return (string.format("%.1f",value):gsub("%.0$","")) end
local function clock(n)
 n=math.max(0,math.floor(n or 0))
 if n>=3600 then return string.format("%d:%02d:%02d",math.floor(n/3600),math.floor(n/60)%60,n%60) end
 return string.format("%d:%02d",math.floor(n/60),n%60)
end
local function opacity(value,minimum,default) return math.max(minimum,math.min(1,tonumber(value) or default)) end
local function stopHandle() if soundHandle then StopSound(soundHandle);soundHandle=nil end end
local function font(parent,template,x,y,width)
 local s=parent:CreateFontString(nil,"OVERLAY",template)
 s:SetPoint("TOPLEFT",x,y);s:SetWidth(width);s:SetJustifyH("LEFT");return s
end
local function button(parent,caption,x,y,width,fn)
 local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
 b:SetPoint("TOPLEFT",x,y);b:SetSize(width,24);b:SetText(caption);b:SetScript("OnClick",fn);return b
end
local function restorePosition(frame,key)
 local p=db and db[key]
 if type(p)=="table" and p[1] and p[2] and type(p[3])=="number" and type(p[4])=="number" then
  frame:ClearAllPoints();frame:SetPoint(p[1],UIParent,p[2],p[3],p[4])
 end
end
local function savePosition(self,key)
 self:StopMovingOrSizing()
 if db then local p,_,rp,x,y=self:GetPoint();db[key]={p,rp,x,y} end
end
local f=CreateFrame("Frame","MaliMusicPlayerFrame",UIParent,"BasicFrameTemplateWithInset")
f:SetSize(610,610);f:SetPoint("CENTER");f:SetMovable(true);f:EnableMouse(true)
f:SetClampedToScreen(true);f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart",f.StartMoving)
f:SetScript("OnDragStop",function(self) savePosition(self,"position") end)
f.TitleText:SetText("MaliMusicPlayer 0.8.3")
f:Hide();table.insert(UISpecialFrames,"MaliMusicPlayerFrame")
local now=font(f,"GameFontHighlight",16,-38,575)
local timing=font(f,"GameFontNormalSmall",16,-64,575);timing:SetText("Stopped")
local progress=CreateFrame("StatusBar",nil,f)
progress:SetPoint("TOPLEFT",18,-87);progress:SetSize(572,7)
progress:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar");progress:SetStatusBarColor(0.25,0.7,1)
progress:SetMinMaxValues(0,1);progress:SetValue(0)
local progressBG=progress:CreateTexture(nil,"BACKGROUND");progressBG:SetAllPoints();progressBG:SetColorTexture(0.1,0.1,0.1,1)
local library=CreateFrame("Frame",nil,f);library:SetAllPoints()
local settings=CreateFrame("Frame",nil,f);settings:SetAllPoints();settings:Hide()
local tabs={}
local function makeTab(index,caption,width)
 local tab=CreateFrame("Button",nil,f)
 tab:SetSize(width,32);tab:SetFrameLevel(math.max(library:GetFrameLevel(),settings:GetFrameLevel())+5)
 if index==1 then tab:SetPoint("TOPLEFT",f,"TOPLEFT",14,-103)
 else tab:SetPoint("TOPLEFT",tabs[index-1],"TOPRIGHT",-6,0) end
 tab.left=tab:CreateTexture(nil,"BACKGROUND");tab.left:SetPoint("TOPLEFT");tab.left:SetSize(20,32)
 tab.right=tab:CreateTexture(nil,"BACKGROUND");tab.right:SetPoint("TOPRIGHT");tab.right:SetSize(20,32)
 tab.middle=tab:CreateTexture(nil,"BACKGROUND")
 tab.middle:SetPoint("TOPLEFT",tab.left,"TOPRIGHT");tab.middle:SetPoint("BOTTOMRIGHT",tab.right,"BOTTOMLEFT")
 tab.caption=tab:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
 tab.caption:SetPoint("CENTER");tab.caption:SetText(caption)
 local hover=tab:CreateTexture(nil,"HIGHLIGHT")
 hover:SetPoint("TOPLEFT",8,-4);hover:SetPoint("BOTTOMRIGHT",-8,5);hover:SetColorTexture(1,1,1,0.08)
 tab:SetScript("OnClick",function() showTab(index==1 and "library" or "settings") end)
 tabs[index]=tab
end
makeTab(1,"Library",104);makeTab(2,"Settings / About",160)
showTab=function(which)
 local selectedTab=which=="settings" and 2 or 1
 library:SetShown(selectedTab==1);settings:SetShown(selectedTab==2)
 for i,tab in ipairs(tabs) do
  local active=i==selectedTab
  local prefix=active and "Interface/PaperDollInfoFrame/UI-Character-ActiveTab-" or "Interface/PaperDollInfoFrame/UI-Character-InActiveTab-"
  tab.left:SetTexture(prefix.."Left");tab.middle:SetTexture(prefix.."Middle");tab.right:SetTexture(prefix.."Right")
  tab.caption:SetTextColor(active and 1 or 0.85,active and 0.82 or 0.85,active and 0 or 0.85)
  tab.caption:ClearAllPoints();tab.caption:SetPoint("CENTER",0,active and 2 or -1);tab:Show()
 end
end
local search=CreateFrame("EditBox",nil,library,"InputBoxTemplate")
search:SetPoint("TOPLEFT",23,-142);search:SetSize(435,24);search:SetAutoFocus(false);search:SetMaxLetters(150)
search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
local resultCount=font(library,"GameFontNormalSmall",477,-149,110);resultCount:SetText("0 tracks")
local scroll=CreateFrame("ScrollFrame","MaliMusicPlayerScroll",library,"FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT",16,-178);scroll:SetSize(553,VISIBLE_ROWS*ROW_HEIGHT)
for i=1,VISIBLE_ROWS do
 local b=CreateFrame("Button",nil,library)
 b:SetPoint("TOPLEFT",16,-178-(i-1)*ROW_HEIGHT);b:SetSize(550,ROW_HEIGHT)
 b:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight","ADD")
 b.title=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 b.title:SetPoint("LEFT",4,0);b.title:SetWidth(470);b.title:SetJustifyH("LEFT")
 b.duration=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");b.duration:SetPoint("RIGHT",-4,0)
 b:SetScript("OnClick",function(self) if self.track then rememberSelection(self.track);play(selected) end end)
 rows[i]=b
end
local compact=CreateFrame("Frame","MaliMusicPlayerCompact",UIParent)
compact:SetSize(210,56);compact:SetPoint("CENTER",UIParent,"CENTER",0,-180)
compact:SetMovable(true);compact:EnableMouse(true);compact:SetClampedToScreen(true);compact:Hide()
local compactBG=compact:CreateTexture(nil,"BACKGROUND");compactBG:SetAllPoints()
local titleViewport=CreateFrame("ScrollFrame",nil,compact)
titleViewport:SetPoint("TOPLEFT",9,-7);titleViewport:SetSize(162,17);titleViewport:EnableMouse(true)
local titleChild=CreateFrame("Frame",nil,titleViewport);titleChild:SetSize(162,17);titleChild:EnableMouse(false);titleViewport:SetScrollChild(titleChild)
local title=titleChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
local fontPath=title:GetFont();title:SetFont(fontPath,11,"")
title:SetPoint("LEFT",titleChild,"LEFT",0,0);title:SetWordWrap(false)
local compactTime=font(compact,"GameFontNormalSmall",10,-34,110)
local timeFont=compactTime:GetFont();compactTime:SetFont(timeFont,11,"");compactTime:SetText("Stopped")
local compactMoving=false
local function finishCompactMove()
 if not compactMoving then return end
 compactMoving=false;savePosition(compact,"compactPosition")
end
local titleRepeat=titleChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
titleRepeat:SetFont(fontPath,11,"");titleRepeat:SetWordWrap(false);titleRepeat:Hide()
local marqueeText,marqueeLimit,marqueePos,marqueeDirection,marqueeWait,marqueeTick=nil,0,0,1,2,0
local marqueeCycle=0
local function scrollMode() return db and db.compactScrollMode or "loop" end
local function loopingTitle() return scrollMode()=="loop" end
local function hideTitleTooltip()
 if GameTooltip:GetOwner()==titleViewport then GameTooltip:Hide() end
end
local function showTitleTooltip()
 if compactMoving or (db and db.compactTitleTooltip==false) then return end
 local index=current or selected
 if not tracks[index] then return end
 GameTooltip:SetOwner(titleViewport,"ANCHOR_TOP")
 GameTooltip:SetText(safe(label(tracks[index])),1,1,1,1,true)
 GameTooltip:Show()
end
titleViewport:SetScript("OnEnter",showTitleTooltip)
titleViewport:SetScript("OnLeave",hideTitleTooltip)
titleViewport:SetScript("OnHide",hideTitleTooltip)
local function resetMarquee()
 local width=math.ceil(title:GetStringWidth())
 local viewportWidth=titleViewport:GetWidth()
 marqueeLimit=math.max(0,width-viewportWidth)
 marqueePos=0;marqueeDirection=1;marqueeWait=2;marqueeTick=0
 title:SetWidth(math.max(width,1))
 titleRepeat:SetText(marqueeText or "");titleRepeat:SetWidth(math.max(width,1))
 marqueeCycle=width+40
 titleRepeat:ClearAllPoints();titleRepeat:SetPoint("LEFT",titleChild,"LEFT",marqueeCycle,0)
 local looping=loopingTitle() and marqueeLimit>0
 titleRepeat:SetShown(looping)
 titleChild:SetWidth(looping and (marqueeCycle+width) or math.max(viewportWidth,width))
 titleViewport:UpdateScrollChildRect();titleViewport:SetHorizontalScroll(0)
end
local function setTitle(value)
 if value==marqueeText then return end
 marqueeText=value;title:SetWidth(0);title:SetText(value);resetMarquee()
 if GameTooltip:GetOwner()==titleViewport and GameTooltip:IsShown() then showTitleTooltip() end
end
compact:SetScript("OnUpdate",function(self,elapsed)
 if compactMoving and not IsMouseButtonDown("LeftButton") then finishCompactMove() end
 if marqueeLimit<=0 or scrollMode()=="static" then return end
 local looping=loopingTitle()
 if not looping and marqueeWait>0 then marqueeWait=math.max(0,marqueeWait-elapsed);return end
 marqueeTick=marqueeTick+elapsed;if marqueeTick<1/30 then return end
 local delta=math.min(marqueeTick,0.1);marqueeTick=0
 if looping then marqueePos=(marqueePos+24*delta)%marqueeCycle
 else
  marqueePos=marqueePos+marqueeDirection*24*delta
  if marqueePos>=marqueeLimit then marqueePos=marqueeLimit;marqueeDirection=-1;marqueeWait=2
  elseif marqueePos<=0 then marqueePos=0;marqueeDirection=1;marqueeWait=2 end
 end
 titleViewport:SetHorizontalScroll(marqueePos)
end)
local function applyOpacity()
 local hovered=false
 for _,b in ipairs(compactButtons) do
  if b.hovered then hovered=true end
  b:SetAlpha(b.hovered and 1 or opacity(db and db.compactButtonOpacity,0.2,0.30))
 end
 local textAlpha=hovered and 1 or opacity(db and db.compactTextOpacity,0.2,0.30)
 title:SetAlpha(textAlpha);titleRepeat:SetAlpha(textAlpha);compactTime:SetAlpha(textAlpha)
 compactBG:SetColorTexture(0.025,0.025,0.025,opacity(db and db.compactBackground,0,0.30))
end
local function hoverHandlers(b,tooltip)
 b:SetScript("OnEnter",function(self)
  self.hovered=true;applyOpacity()
  GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(tooltip);GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function(self) self.hovered=false;applyOpacity();GameTooltip:Hide() end)
 b:SetScript("OnHide",function(self) self.hovered=false;applyOpacity();GameTooltip:Hide() end)
 compactButtons[#compactButtons+1]=b
end
local function iconButton(x,y,texture,tooltip,fn)
 local b=CreateFrame("Button",nil,compact)
 b:SetPoint("TOPLEFT",x,y);b:SetSize(23,23)
 local bg=b:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.08,0.08,0.08,0.4)
 if texture then
  b:SetNormalTexture(texture)
  local t=b:GetNormalTexture();t:ClearAllPoints();t:SetPoint("CENTER");t:SetSize(21,21)
 else
  local t=b:CreateTexture(nil,"ARTWORK");t:SetSize(9,9);t:SetPoint("CENTER");t:SetColorTexture(0.95,0.8,0.35,1)
 end
 local highlight=b:CreateTexture(nil,"HIGHLIGHT");highlight:SetAllPoints();highlight:SetColorTexture(1,1,1,0.15)
 b:SetScript("OnClick",fn);hoverHandlers(b,tooltip);return b
end
local function updateCompactStatus()
 if GetCVar("Sound_EnableMusic")=="0" then compactTime:SetText("Music disabled");return end
 if not playing or not current or not tracks[current] then compactTime:SetText("Stopped");return end
 local duration=tracks[current].duration or 0
 local elapsed=math.max(0,GetTime()-started)
 compactTime:SetText(clock(elapsed).." / "..(duration>0 and clock(duration) or "--:--"))
end
local function updateTime()
 if not current then return end
 local duration=tracks[current].duration or 0;local elapsed=math.max(0,GetTime()-started)
 if duration>0 then
  timing:SetText("Elapsed "..clock(elapsed).."   |   Remaining -"..clock(duration-elapsed).."   |   Total "..clock(duration))
  progress:SetValue(math.min(1,elapsed/duration))
 else
  timing:SetText("Elapsed "..clock(elapsed).."   |   Duration unknown: regenerate library or use Next")
  progress:SetValue(0)
 end
 updateCompactStatus()
end
refresh=function()
 FauxScrollFrame_Update(scroll,#filtered,VISIBLE_ROWS,ROW_HEIGHT)
 local offset=FauxScrollFrame_GetOffset(scroll)
 for i,b in ipairs(rows) do
  local index=filtered[offset+i];b.track=index
  if index then
   local t=tracks[index];b.title:SetText((playing and current==index and "> " or "")..safe(label(t)))
   b.duration:SetText((t.duration or 0)>0 and clock(t.duration) or "--:--");b:Show()
  else b:Hide() end
 end
 if current then now:SetText((playing and "Playing: " or "Stopped: ")..safe(label(tracks[current])))
 elseif tracks[selected] then now:SetText("Selected: "..safe(label(tracks[selected])))
 else now:SetText("Select a song to play.") end
 local index=current or selected
 setTitle(tracks[index] and safe(label(tracks[index])) or "MaliMusicPlayer")
 updateCompactStatus()
end
local function rebuild()
 wipe(filtered);local q=string.lower(search:GetText() or "")
 for i,t in ipairs(tracks) do if q=="" or string.find(string.lower(label(t)),q,1,true) then filtered[#filtered+1]=i end end
 if q=="" then resultCount:SetText(#tracks..(#tracks==1 and " track" or " tracks"))
 else resultCount:SetText(#filtered.." of "..#tracks) end
 FauxScrollFrame_SetOffset(scroll,0);if scroll.ScrollBar then scroll.ScrollBar:SetValue(0) end;refresh()
end
scroll:SetScript("OnVerticalScroll",function(self,offset) FauxScrollFrame_OnVerticalScroll(self,offset,ROW_HEIGHT,refresh) end)
search:SetScript("OnTextChanged",rebuild)
local function stop()
 playing=false;stopHandle();StopMusic()
 timing:SetText("Stopped");compactTime:SetText("Stopped");progress:SetValue(0)
 trace("Stop.");refresh()
end
play=function(index)
 if not tracks[index] then say("No tracks. Run UpdateLibrary.cmd, then restart WoW.");return end
 if GetCVar("Sound_EnableAllSound")=="0" then
  say("Enable sound in WoW's audio settings.");refresh();return
 end
 if GetCVar("Sound_EnableMusic")=="0" then
  say("Music is disabled. Click Music: Off beside the volume slider to enable it, then press Play.");refresh();return
 end
 -- Do not silently alter an external mute or start a sound on a zero-volume channel.
 if musicVolume()<=0 then
  say("Music volume is 0% outside this player. Raise the slider, then press Play.");refresh();return
 end
 stopHandle();playing=false;PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg")
 local ok,handle=PlaySoundFile(tracks[index].path,"Music")
 current=index;rememberSelection(index)
 trace("Play: track="..index.." volume="..musicVolume().." success="..tostring(ok).." handle="..tostring(handle))
 if not ok or not handle then
  StopMusic();timing:SetText("Playback failed. Check the file path / audio settings, then use Play to retry.")
  progress:SetValue(0);refresh()
  if GetCVar("Sound_EnableMusic")~="0" then compactTime:SetText("Playback failed") end
  say("Could not start: "..safe(label(tracks[index])));return
 end
 soundHandle=handle;started=GetTime();playing=true;updateTime();refresh()
end
advance=function(direction,automatic)
 if #tracks==0 then return end
 local index=current or selected or 1
 if automatic and db and db.repeatTrack then play(index);return end
 if db and db.shuffle and #tracks>1 then local n=math.random(#tracks-1);if n>=index then n=n+1 end;index=n
 else index=((index-1+direction)%#tracks)+1 end
 play(index)
end
button(library,"Previous",16,-529,88,function() advance(-1,false) end)
button(library,"Play",110,-529,70,function() play(selected) end)
button(library,"Stop",186,-529,70,stop)
button(library,"Next",262,-529,70,function() advance(1,false) end)
local shuffle=button(library,"Shuffle: Off",338,-529,120,function() if db then db.shuffle=not db.shuffle;sync() end end)
local repeatButton=button(library,"Repeat: Off",464,-529,130,function() if db then db.repeatTrack=not db.repeatTrack;sync() end end)
sync=function()
 shuffle:SetText(db and db.shuffle and "Shuffle: On" or "Shuffle: Off")
 repeatButton:SetText(db and db.repeatTrack and "Repeat: On" or "Repeat: Off")
end
local volumeLabel=font(f,"GameFontNormalSmall",18,-578,160)
local volume=CreateFrame("Slider",nil,f,"OptionsSliderTemplate")
volume:SetPoint("TOPLEFT",180,-576);volume:SetSize(210,16)
volume:SetMinMaxValues(MIN_VOLUME_PERCENT,100);volume:SetValueStep(0.1)
if volume.SetObeyStepOnDrag then volume:SetObeyStepOnDrag(true) end
local updatingVolume=false
local function syncVolume()
 -- Programmatic synchronization must never write a rounded value back to the CVar.
 updatingVolume=true
 local actual=musicVolume()*100
 volume:SetValue(sliderPercent(actual))
 if actual<=0 then
  volumeLabel:SetText("Music volume: 0% (external)")
 elseif actual<MIN_VOLUME_PERCENT then
  volumeLabel:SetText("Music volume: <0.1%")
 else
  volumeLabel:SetText("Music volume: "..percentText(actual).."%")
 end
 updatingVolume=false
end
volume:SetScript("OnValueChanged",function(self,value)
 if updatingVolume then return end
 local percent=sliderPercent(value)
 -- 0.1 percent / 100 is a 0.001 CVar value, not 0.1 (which would be 10 percent).
 SetCVar("Sound_MusicVolume",percent/100)
 trace("Slider: "..percentText(percent).."%; CVar="..musicVolume())
 syncVolume()
end)
volume:SetScript("OnEnter",function(self)
 GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Music volume")
 GameTooltip:AddLine("0.1%-100%. The minimum is quiet, not mute. Use Stop for silence.",1,1,1,true)
 GameTooltip:AddLine("Changing volume does not restart the track.",1,1,1,true);GameTooltip:Show()
end)
volume:SetScript("OnLeave",function() GameTooltip:Hide() end)
volume:SetScript("OnHide",function() GameTooltip:Hide() end)
local musicToggle
local function syncMusicToggle()
 if musicToggle then musicToggle:SetText(GetCVar("Sound_EnableMusic")=="1" and "Music: On" or "Music: Off") end
 updateCompactStatus()
end
musicToggle=button(f,"Music: Off",400,-575,94,function()
 local enabled=GetCVar("Sound_EnableMusic")=="1"
 SetCVar("Sound_EnableMusic",enabled and "0" or "1")
 syncMusicToggle()
end)
musicToggle:SetScript("OnEnter",function(self)
 GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Enable / disable music")
 GameTooltip:AddLine("Changes WoW's Music setting directly. No keyboard shortcut required.",1,1,1,true)
 GameTooltip:AddLine("Enable music here, then press Play to listen to your tracks.",1,1,1,true)
 GameTooltip:AddLine("Does not change your volume or start / restart a track.",1,1,1,true)
 GameTooltip:Show()
end)
musicToggle:SetScript("OnLeave",function() GameTooltip:Hide() end)
musicToggle:SetScript("OnHide",function() GameTooltip:Hide() end)
f:SetScript("OnShow",function() syncVolume();syncMusicToggle() end)
setCompact=function(enabled)
 if db then db.compactMode=enabled end
 if enabled then f:Hide();applyOpacity();updateCompactStatus();compact:Show() else compact:Hide();f:Show() end
end
f:HookScript("OnHide",function()
 if not playing then return end
 if db then db.compactMode=true end
 applyOpacity();updateCompactStatus();compact:Show()
end)
togglePlayer=function()
 if f:IsShown() then f:Hide()
 elseif compact:IsShown() then compact:Hide()
 elseif db and db.compactMode then setCompact(true)
 else showTab("library");setCompact(false) end
end
button(f,"Compact",500,-575,92,function() setCompact(true) end)
local expandButton=iconButton(179,-4,"Interface/Buttons/UI-PlusButton-UP","Open full player",function() showTab("library");setCompact(false) end)
local previousButton=iconButton(128,-29,"Interface/Buttons/UI-SpellbookIcon-PrevPage-Up","Previous track",function() advance(-1,false) end)
local stopButton=iconButton(154,-29,nil,"Stop playback",stop)
local nextButton=iconButton(180,-29,"Interface/Buttons/UI-SpellbookIcon-NextPage-Up","Next track",function() advance(1,false) end)
local function compactWidth(value)
 return math.max(180,math.min(360,math.floor((tonumber(value) or 210)+0.5)))
end
local function applyCompactWidth(value)
 local width=compactWidth(value)
 compact:SetWidth(width);titleViewport:SetWidth(width-48);compactTime:SetWidth(width-100)
 expandButton:ClearAllPoints();expandButton:SetPoint("TOPRIGHT",compact,"TOPRIGHT",-8,-4)
 previousButton:ClearAllPoints();previousButton:SetPoint("TOPRIGHT",compact,"TOPRIGHT",-59,-29)
 stopButton:ClearAllPoints();stopButton:SetPoint("TOPRIGHT",compact,"TOPRIGHT",-33,-29)
 nextButton:ClearAllPoints();nextButton:SetPoint("TOPRIGHT",compact,"TOPRIGHT",-7,-29)
 resetMarquee()
end
font(settings,"GameFontNormal",20,-147,555):SetText("Compact appearance")
local opacityInitializing=false
local function opacityControl(y,caption,key,minimum)
 local captionText=font(settings,"GameFontHighlightSmall",24,y,240)
 local slider=CreateFrame("Slider",nil,settings,"OptionsSliderTemplate")
 slider:SetPoint("TOPLEFT",280,y);slider:SetSize(270,16);slider:SetMinMaxValues(minimum,100);slider:SetValueStep(1)
 if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
 slider:SetScript("OnValueChanged",function(self,value)
  value=math.floor(value+0.5);captionText:SetText(caption..": "..value.."%")
  if db and not opacityInitializing then db[key]=value/100 end;applyOpacity()
 end)
 return slider
end
local backgroundSlider=opacityControl(-174,"Background opacity","compactBackground",0)
local textSlider=opacityControl(-204,"Text opacity","compactTextOpacity",20)
local buttonSlider=opacityControl(-234,"Button opacity","compactButtonOpacity",20)
font(settings,"GameFontDisableSmall",24,-264,550):SetText("Hover a compact button to brighten it and the title / timer to 100%.")
font(settings,"GameFontHighlightSmall",24,-285,240):SetText("Title scrolling")
local scrollModeButton
local function syncScrollMode()
 local mode=scrollMode()
 scrollModeButton:SetText(mode=="static" and "Stationary" or (mode=="bounce" and "Back-and-forth" or "Continuous loop"))
end
scrollModeButton=button(settings,"Continuous loop",280,-280,270,function()
 if not db then return end
 local mode=scrollMode()
 db.compactScrollMode=mode=="loop" and "bounce" or (mode=="bounce" and "static" or "loop")
 syncScrollMode();resetMarquee()
end)
font(settings,"GameFontDisableSmall",24,-310,550):SetText("Click to cycle: continuous / back-and-forth / stationary. Choice is saved.")
local widthLabel=font(settings,"GameFontHighlightSmall",24,-338,240)
local widthSlider=CreateFrame("Slider",nil,settings,"OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT",280,-336);widthSlider:SetSize(270,16)
widthSlider:SetMinMaxValues(180,360);widthSlider:SetValueStep(1)
if widthSlider.SetObeyStepOnDrag then widthSlider:SetObeyStepOnDrag(true) end
widthSlider:SetScript("OnValueChanged",function(self,value)
 local width=compactWidth(value)
 widthLabel:SetText("Compact width: "..width.." px")
 if db and not opacityInitializing then db.compactWidth=width end
 applyCompactWidth(width)
end)
font(settings,"GameFontDisableSmall",24,-363,550):SetText("180-360 px. Default: 210 px. Width updates immediately and is saved.")
local fullOpacityLabel=font(settings,"GameFontHighlightSmall",24,-390,240)
local fullOpacitySlider=CreateFrame("Slider",nil,settings,"OptionsSliderTemplate")
fullOpacitySlider:SetPoint("TOPLEFT",280,-388);fullOpacitySlider:SetSize(270,16)
fullOpacitySlider:SetMinMaxValues(33,100);fullOpacitySlider:SetValueStep(1)
if fullOpacitySlider.SetObeyStepOnDrag then fullOpacitySlider:SetObeyStepOnDrag(true) end
fullOpacitySlider:SetScript("OnValueChanged",function(self,value)
 local alpha=opacity(math.floor(value+0.5)/100,0.33,0.70)
 fullOpacityLabel:SetText("Full player opacity: "..math.floor(alpha*100+0.5).."%")
 if db and not opacityInitializing then db.fullPlayerOpacity=alpha end
 f:SetAlpha(alpha)
end)
font(settings,"GameFontDisableSmall",232,-414,330):SetText("Full player opacity: 33-100%; compact is separate.")
local titleTooltipCheck=CreateFrame("CheckButton",nil,settings,"UICheckButtonTemplate")
titleTooltipCheck:SetPoint("TOPLEFT",22,-430);titleTooltipCheck:SetSize(24,24)
font(settings,"GameFontHighlightSmall",50,-437,260):SetText("Show compact title tooltip")
titleTooltipCheck:SetScript("OnClick",function(self)
 if not db then return end
 db.compactTitleTooltip=self:GetChecked() and true or false
 if not db.compactTitleTooltip then hideTitleTooltip() end
end)
button(settings,"Reset Compact Position",330,-430,220,function()
 finishCompactMove();hideTitleTooltip()
 compact:ClearAllPoints();compact:SetPoint("CENTER",UIParent,"CENTER",0,-180)
 if db then db.compactPosition=nil end
end)
font(settings,"GameFontNormal",20,-470,555):SetText("About")
font(settings,"GameFontHighlightSmall",24,-489,555):SetText("MaliMusicPlayer v0.8.3 - By Mali Gnosis, for Mali Gnosis.")
local quote=font(settings,"GameFontHighlightSmall",24,-508,555)
quote:SetWordWrap(false)
quote:SetText('"If I throw a dog a bone, I don\'t want to know if it tastes good or not." - Brick Top')
local quoteFont=quote:GetFont()
for size=11,8,-0.5 do quote:SetFont(quoteFont,size,"");if quote:GetStringWidth()<=555 then break end end
font(settings,"GameFontDisableSmall",24,-536,555):SetText("Released under the MIT License. See LICENSE.MD for details.")
font(settings,"GameFontHighlightSmall",24,-557,55):SetText("GitHub:")
local repositoryURL="https://github.com/ZiRRuSH/MMP"
local repository=CreateFrame("EditBox",nil,settings,"InputBoxTemplate")
repository:SetPoint("TOPLEFT",86,-551);repository:SetSize(475,22)
repository:SetAutoFocus(false);repository:SetMaxLetters(200);repository:SetText(repositoryURL)
repository:SetCursorPosition(0)
local restoringRepository=false
repository:SetScript("OnTextChanged",function(self)
 if restoringRepository or self:GetText()==repositoryURL then return end
 restoringRepository=true;self:SetText(repositoryURL);self:SetCursorPosition(0);restoringRepository=false
end)
repository:SetScript("OnEditFocusGained",function(self) self:HighlightText() end)
repository:SetScript("OnEditFocusLost",function(self) self:HighlightText(0,0) end)
repository:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
repository:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
repository:SetScript("OnHide",function(self) self:ClearFocus() end)
showTab("library")
local menu=CreateFrame("Frame","MaliMusicPlayerQuickControls",compact)
menu:SetSize(244,256);menu:SetFrameStrata("DIALOG");menu:SetClampedToScreen(true);menu:EnableMouse(true);menu:Hide()
table.insert(UISpecialFrames,"MaliMusicPlayerQuickControls")
local menuBG=menu:CreateTexture(nil,"BACKGROUND");menuBG:SetAllPoints();menuBG:SetColorTexture(0.025,0.025,0.035,0.98)
font(menu,"GameFontNormal",10,-10,224):SetText("MaliMusicPlayer - Quick controls")
local menuTrack=font(menu,"GameFontHighlightSmall",10,-32,224);menuTrack:SetWordWrap(false)
local function action(y,text,fn) return button(menu,text,8,y,228,function() menu:Hide();fn() end) end
action(-55,"Play / restart current track",function() play(current or selected) end)
action(-82,"Stop",stop)
action(-109,"Previous track",function() advance(-1,false) end)
action(-136,"Next track",function() advance(1,false) end)
local menuShuffle=action(-163,"Shuffle: Off",function() if db then db.shuffle=not db.shuffle;sync() end end)
local menuRepeat=action(-190,"Repeat: Off",function() if db then db.repeatTrack=not db.repeatTrack;sync() end end)
action(-217,"Open Settings / About",function() showTab("settings");setCompact(false) end)
local function toggleMenu()
 if menu:IsShown() then menu:Hide();return end
 local index=current or selected
 menuTrack:SetText(tracks[index] and safe(label(tracks[index])) or "No track selected")
 menuShuffle:SetText(db and db.shuffle and "Shuffle: On" or "Shuffle: Off")
 menuRepeat:SetText(db and db.repeatTrack and "Repeat: On" or "Repeat: Off")
 local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale()
 menu:ClearAllPoints();menu:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x/scale+8,y/scale+8);menu:Show();GameTooltip:Hide()
end
local away=0
menu:SetScript("OnShow",function() away=0 end)
menu:SetScript("OnUpdate",function(self,dt)
 if self:IsMouseOver() or compact:IsMouseOver() then away=0
 else away=away+dt;if away>0.6 then self:Hide() end end
end)
local function compactMouseDown(self,which)
 if which~="LeftButton" then return end
 menu:Hide();hideTitleTooltip();GameTooltip:Hide()
 if not compactMoving then compactMoving=true;compact:StartMoving() end
end
local function compactMouseUp(self,which)
 if which=="LeftButton" then finishCompactMove()
 elseif which=="RightButton" and not compactMoving then toggleMenu() end
end
for _,surface in ipairs({compact,titleViewport}) do
 surface:SetScript("OnMouseDown",compactMouseDown);surface:SetScript("OnMouseUp",compactMouseUp)
end
compact:HookScript("OnHide",function() finishCompactMove();menu:Hide();hideTitleTooltip();GameTooltip:Hide() end)

-- Optional integration: reuse libraries supplied by another installed addon.
-- No bundled libraries or required dependencies; custom fallback remains available.
local minimapButton
local minimapBroker
local minimapRetryFrame
local MINIMAP_LAUNCHER="MaliMusicPlayer"
local function openFromMinimap()
 showTab("library");setCompact(false)
end
local function createStandardMinimapButton()
 local stub=_G.LibStub
 if not stub then return false end
 local icon=stub:GetLibrary("LibDBIcon-1.0",true)
 local broker=stub:GetLibrary("LibDataBroker-1.1",true)
 if not icon or not broker or not db then return false end
 if type(db.minimap)~="table" then db.minimap={} end
 if tonumber(db.minimap.minimapPos)==nil then db.minimap.minimapPos=tonumber(db.minimapAngle) or 225 end
 if db.minimap.hide==nil then db.minimap.hide=false end
 local object=broker:GetDataObjectByName(MINIMAP_LAUNCHER)
 if not object then
  object=broker:NewDataObject(MINIMAP_LAUNCHER,{
   type="launcher",
   text="MaliMusicPlayer",
   icon="Interface/ICONS/ClassIcon_Warlock",
   OnClick=function(_,which)
    if which=="LeftButton" or which=="RightButton" then openFromMinimap() end
   end,
   OnTooltipShow=function(tooltip)
    tooltip:AddLine("MaliMusicPlayer")
    if current and tracks[current] then
     tooltip:AddLine((playing and "Playing: " or "Stopped: ")..safe(label(tracks[current])),1,1,1,true)
    end
    tooltip:AddLine("Left/right-click: open full Library view",0.75,0.85,1)
    tooltip:AddLine("Drag to reposition",0.75,0.85,1)
   end,
  })
 end
 minimapBroker=object
 if not icon:IsRegistered(MINIMAP_LAUNCHER) then icon:Register(MINIMAP_LAUNCHER,object,db.minimap)
 else icon:Refresh(MINIMAP_LAUNCHER,db.minimap) end
 local standard=icon:GetMinimapButton(MINIMAP_LAUNCHER)
 if not standard then return false end
 local old=minimapButton
 if old and old~=standard then
  old:SetScript("OnUpdate",nil);old:EnableMouse(false);old:Hide();old:SetParent(nil);old:ClearAllPoints()
 end
 minimapButton=standard
 if minimapRetryFrame then minimapRetryFrame:UnregisterAllEvents() end
 trace("0.8.3 minimap: LibDBIcon active; Warlock launcher registered.")
 return true
end
local function createFallbackMinimapButton()
 if minimapButton or not Minimap then return end
 local b=CreateFrame("Button","MaliMusicPlayerMinimapButton",Minimap);minimapButton=b
 b:SetSize(32,32);b:SetFrameStrata("MEDIUM");b:SetFrameLevel(Minimap:GetFrameLevel()+10)
 b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp");b:RegisterForDrag("LeftButton")
 local icon=b:CreateTexture(nil,"ARTWORK")
 icon:SetSize(20,20);icon:SetPoint("TOPLEFT",7,-5)
 icon:SetTexture("Interface/ICONS/ClassIcon_Warlock");icon:SetTexCoord(0.08,0.92,0.08,0.92)
 local border=b:CreateTexture(nil,"OVERLAY")
 border:SetSize(54,54);border:SetPoint("TOPLEFT");border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
 b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight","ADD")
 local saved=db and type(db.minimap)=="table" and db.minimap.minimapPos
 local angle=tonumber(saved) or tonumber(db and db.minimapAngle) or 225
 local dragging,wasDragged=false,false
 local function position()
  if minimapButton~=b then return end
  local a=math.rad(angle);local rx=Minimap:GetWidth()/2+8;local ry=Minimap:GetHeight()/2+8
  b:ClearAllPoints();b:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*rx,math.sin(a)*ry)
 end
 local function cursorAngle()
  local x,y=GetCursorPosition();local scale=Minimap:GetEffectiveScale()
  local cx,cy=Minimap:GetCenter();if not cx or not cy then return end
  local dx,dy=x/scale-cx,y/scale-cy;if dx==0 and dy==0 then return end
  local a
  if dx==0 then a=dy>0 and math.pi/2 or -math.pi/2
  else a=math.atan(dy/dx);if dx<0 then a=a+math.pi end end
  angle=math.deg(a)%360;position()
 end
 local function finishDrag()
  if not dragging then return end
  dragging=false
  if db then
   db.minimapAngle=angle
   if type(db.minimap)~="table" then db.minimap={} end
   db.minimap.minimapPos=angle
  end
 end
 b:SetScript("OnMouseDown",function(self,which) if which=="LeftButton" then wasDragged=false end end)
 b:SetScript("OnDragStart",function() dragging=true;wasDragged=true;GameTooltip:Hide();cursorAngle() end)
 b:SetScript("OnDragStop",finishDrag)
 b:SetScript("OnMouseUp",function(self,which) if which=="LeftButton" then finishDrag() end end)
 b:SetScript("OnUpdate",function()
  if dragging then cursorAngle();if not IsMouseButtonDown("LeftButton") then finishDrag() end end
 end)
 b:SetScript("OnClick",function() if not wasDragged then openFromMinimap() end end)
 b:SetScript("OnEnter",function(self)
  if dragging then return end
  GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText("MaliMusicPlayer")
  if current and tracks[current] then
   GameTooltip:AddLine((playing and "Playing: " or "Stopped: ")..safe(label(tracks[current])),1,1,1,true)
  end
  GameTooltip:AddLine("Left/right-click: open full Library view",0.75,0.85,1)
  GameTooltip:AddLine("Drag to reposition",0.75,0.85,1);GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() GameTooltip:Hide() end)
 b:SetScript("OnHide",function() finishDrag();GameTooltip:Hide() end)
 Minimap:HookScript("OnSizeChanged",position);position()
 if not (db and type(db.minimap)=="table" and db.minimap.hide) then b:Show() else b:Hide() end
 say("0.8.3 minimap: custom fallback; LibDBIcon/LibDataBroker not loaded. Warning may remain.")
end
local function createMinimapButton()
 if minimapButton or minimapRetryFrame then return end
 minimapRetryFrame=CreateFrame("Frame")
 minimapRetryFrame:RegisterEvent("ADDON_LOADED")
 minimapRetryFrame:SetScript("OnEvent",function()
  C_Timer.After(0,function() createStandardMinimapButton() end)
 end)
 -- Run after all PLAYER_LOGIN handlers, so other addons can initialize first.
 C_Timer.After(0,function()
  if not createStandardMinimapButton() then createFallbackMinimapButton() end
 end)
end

local function openPlayerSettings()
 if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Hide() end
 if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
 if GameMenuFrame and GameMenuFrame:IsShown() then GameMenuFrame:Hide() end
 showTab("settings");setCompact(false)
end
local optionsRegistered=false
local function registerOptionsPanel()
 if optionsRegistered then return end
 local panel=CreateFrame("Frame","MaliMusicPlayerOptionsPanel",UIParent);panel.name="MaliMusicPlayer";panel:Hide()
 font(panel,"GameFontNormalLarge",20,-20,540):SetText("MaliMusicPlayer")
 font(panel,"GameFontHighlight",20,-55,540):SetText("Your music, in-game.")
 font(panel,"GameFontHighlightSmall",20,-86,540):SetText("Open the player to manage your library, playback, and appearance settings.")
 button(panel,"Open Player Settings",20,-135,190,openPlayerSettings)
 font(panel,"GameFontDisableSmall",20,-178,540):SetText("Prefer a shortcut? Type /mmp to open the player.")
 if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local category=Settings.RegisterCanvasLayoutCategory(panel,"MaliMusicPlayer");Settings.RegisterAddOnCategory(category);optionsRegistered=true
 elseif InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel);optionsRegistered=true
 else say("Blizzard's AddOns settings registration is unavailable. /mmp still works.") end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGIN","LOADING_SCREEN_ENABLED","LOADING_SCREEN_DISABLED","CVAR_UPDATE","PLAYER_LOGOUT"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(self,event,name)
 if event=="ADDON_LOADED" and name=="MaliMusicPlayer" then
  MaliMusicPlayerDB=MaliMusicPlayerDB or {};db=MaliMusicPlayerDB
  db.compactBackground=opacity(db.compactBackground,0,0.30)
  db.compactTextOpacity=opacity(db.compactTextOpacity,0.2,0.30)
  db.compactButtonOpacity=opacity(db.compactButtonOpacity,0.2,0.30)
  db.fullPlayerOpacity=opacity(db.fullPlayerOpacity,0.33,0.70)
  -- Preserve valid existing scroll choices, including the new static mode.
  local mode=db.compactScrollMode
  if mode~="loop" and mode~="bounce" and mode~="static" then db.compactScrollMode="loop" end
  db.compactDefaults077=true
  if db.compactTitleTooltip==nil then db.compactTitleTooltip=true end
  titleTooltipCheck:SetChecked(db.compactTitleTooltip and true or false)
  restoreSelection()
  db.compactWidth=compactWidth(db.compactWidth);syncScrollMode()
  restorePosition(f,"position");restorePosition(compact,"compactPosition")
  applyCompactWidth(db.compactWidth);sync();rebuild();syncVolume();syncMusicToggle();opacityInitializing=true
  backgroundSlider:SetValue(db.compactBackground*100);textSlider:SetValue(db.compactTextOpacity*100);buttonSlider:SetValue(db.compactButtonOpacity*100)
  widthSlider:SetValue(db.compactWidth);widthLabel:SetText("Compact width: "..db.compactWidth.." px")
  fullOpacitySlider:SetValue(db.fullPlayerOpacity*100)
  fullOpacityLabel:SetText("Full player opacity: "..math.floor(db.fullPlayerOpacity*100+0.5).."%")
  f:SetAlpha(db.fullPlayerOpacity);opacityInitializing=false;applyOpacity()
  local unknown=0;for _,t in ipairs(tracks) do if (t.duration or 0)<=0 then unknown=unknown+1 end end
  say("v0.8.3: "..#tracks.." tracks; "..unknown.." unknown durations. /mmp to open.")
 elseif event=="PLAYER_LOGIN" then registerOptionsPanel();createMinimapButton()
 elseif event=="LOADING_SCREEN_ENABLED" then loading=true
 elseif event=="LOADING_SCREEN_DISABLED" then
  loading=false
  if playing then
   updateTime()
   C_Timer.After(1,function() if playing and not loading then PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg") end end)
  end
 elseif event=="CVAR_UPDATE" then
  syncMusicToggle()
  if f:IsShown() then syncVolume() end
 elseif event=="PLAYER_LOGOUT" then playing=false;stopHandle();StopMusic() end
end)
local tick=0
events:SetScript("OnUpdate",function(self,elapsed)
 if not playing or loading then return end
 tick=tick+elapsed;if tick<0.2 then return end;tick=0
 -- An external mute is not silently undone. Stop tracking playback; Play is explicit recovery.
 if musicVolume()<=0 then
  stop();timing:SetText("Music muted outside this player. Raise volume, then press Play.")
  if GetCVar("Sound_EnableMusic")~="0" then compactTime:SetText("Muted externally") end
  trace("External zero detected; stopped without automatic recovery.");return
 end
 updateTime();local duration=tracks[current].duration or 0
 if duration>0 and GetTime()-started>=duration+0.4 then advance(1,true) end
end)
SLASH_MALIMUSICPLAYER1="/malimusicplayer"
SLASH_MALIMUSICPLAYER2="/mmp"
SLASH_MALIMUSICPLAYER3="/musicplayer"
SLASH_MALIMUSICPLAYER4="/malimusic"
SlashCmdList.MALIMUSICPLAYER=function(msg)
 msg=string.lower(strtrim(msg or ""))
 if msg=="compact" then setCompact(true)
 elseif msg=="full" then showTab("library");setCompact(false)
 elseif msg=="stop" then stop()
 elseif msg=="next" then advance(1,false)
 elseif msg=="prev" then advance(-1,false)
 elseif msg=="play" then play(selected)
 else togglePlayer() end
end
SLASH_MALIMUSICPLAYERDIAG1="/mmpdiag"
SlashCmdList.MALIMUSICPLAYERDIAG=function(msg)
 msg=string.lower(strtrim(msg or ""))
 if msg=="on" then diagnostics=true;say("Audio diagnostics enabled for this session.")
 elseif msg=="off" then diagnostics=false;say("Audio diagnostics disabled.")
 elseif msg~="status" and msg~="" then say("/mmpdiag on | off | status");return end
 say("[audio] volume="..musicVolume().." playing="..tostring(playing).." handle="..tostring(soundHandle).." track="..tostring(current).." selected="..tostring(selected).." allSound="..tostring(GetCVar("Sound_EnableAllSound")).." musicEnabled="..tostring(GetCVar("Sound_EnableMusic")))
end
