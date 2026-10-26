-- MaliMusicPlayer 0.7.2 Experimental
-- Working 0.6.2 Experimental 2 design plus a standalone Warlock minimap button.
-- Keep your trusted 0.6.1 and working 0.6.2.x2 copies outside the addon folder.
local tracks=MaliMusicPlayerLibrary or {}
local db,current,selected,started=nil,nil,1,0
local playing,loading,soundHandle=false,false,nil
local refresh,play,advance,sync,setCompact,togglePlayer,showTab
local filtered,rows,compactButtons={},{},{}
local function say(s) print("|cff70cfffMaliMusicPlayer:|r "..s) end
local function safe(s) return (tostring(s or ""):gsub("|","||")) end
local function label(t)
 return (t.artist and t.artist~="" and t.artist.." - " or "")..(t.title or "Untitled")
end
local function clock(n)
 n=math.max(0,math.floor(n or 0))
 if n>=3600 then return string.format("%d:%02d:%02d",math.floor(n/3600),math.floor(n/60)%60,n%60) end
 return string.format("%d:%02d",math.floor(n/60),n%60)
end
local function opacity(value,minimum,default)
 return math.max(minimum,math.min(1,tonumber(value) or default))
end
local function stopHandle()
 if soundHandle then StopSound(soundHandle);soundHandle=nil end
end
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
f:SetSize(610,520);f:SetPoint("CENTER");f:SetMovable(true);f:EnableMouse(true)
f:SetClampedToScreen(true);f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart",f.StartMoving)
f:SetScript("OnDragStop",function(self) savePosition(self,"position") end)
f.TitleText:SetText("MaliMusicPlayer 0.7.2 Experimental")
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
font(library,"GameFontNormalSmall",477,-149,110):SetText("Search library")
local scroll=CreateFrame("ScrollFrame","MaliMusicPlayerScroll",library,"FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT",16,-178);scroll:SetSize(553,216)
for i=1,9 do
 local b=CreateFrame("Button",nil,library)
 b:SetPoint("TOPLEFT",16,-178-(i-1)*24);b:SetSize(550,24)
 b:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight","ADD")
 b.title=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 b.title:SetPoint("LEFT",4,0);b.title:SetWidth(470);b.title:SetJustifyH("LEFT")
 b.duration=b:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");b.duration:SetPoint("RIGHT",-4,0)
 b:SetScript("OnClick",function(self) if self.track then selected=self.track;play(selected) end end)
 rows[i]=b
end
local compact=CreateFrame("Frame","MaliMusicPlayerCompact",UIParent)
compact:SetSize(300,56);compact:SetPoint("CENTER",UIParent,"CENTER",0,-180)
compact:SetMovable(true);compact:EnableMouse(true);compact:SetClampedToScreen(true)
compact:Hide();table.insert(UISpecialFrames,"MaliMusicPlayerCompact")
local compactBG=compact:CreateTexture(nil,"BACKGROUND");compactBG:SetAllPoints()
local titleViewport=CreateFrame("ScrollFrame",nil,compact)
titleViewport:SetPoint("TOPLEFT",9,-7);titleViewport:SetSize(252,17);titleViewport:EnableMouse(true)
local titleChild=CreateFrame("Frame",nil,titleViewport);titleChild:SetSize(252,17);titleChild:EnableMouse(false);titleViewport:SetScrollChild(titleChild)
local title=titleChild:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
local fontPath=title:GetFont();title:SetFont(fontPath,11,"")
title:SetPoint("LEFT",titleChild,"LEFT",0,0);title:SetWordWrap(false)
local compactTime=font(compact,"GameFontNormalSmall",10,-34,180)
local timeFont=compactTime:GetFont();compactTime:SetFont(timeFont,11,"");compactTime:SetText("Stopped")
local compactMoving=false
local function finishCompactMove()
 if not compactMoving then return end
 compactMoving=false;savePosition(compact,"compactPosition")
end
local marqueeText,marqueeLimit,marqueePos,marqueeDirection,marqueeWait,marqueeTick=nil,0,0,1,2,0
local function setTitle(value)
 if value==marqueeText then return end
 marqueeText=value;title:SetWidth(0);title:SetText(value)
 local width=math.ceil(title:GetStringWidth())
 title:SetWidth(math.max(width,1));titleChild:SetWidth(math.max(252,width));titleViewport:UpdateScrollChildRect()
 marqueeLimit=math.max(0,width-252);marqueePos=0;marqueeDirection=1;marqueeWait=2;marqueeTick=0
 titleViewport:SetHorizontalScroll(0)
end
compact:SetScript("OnUpdate",function(self,elapsed)
 if compactMoving and not IsMouseButtonDown("LeftButton") then finishCompactMove() end
 if marqueeLimit<=0 then return end
 if marqueeWait>0 then marqueeWait=math.max(0,marqueeWait-elapsed);return end
 marqueeTick=marqueeTick+elapsed;if marqueeTick<1/30 then return end
 local delta=math.min(marqueeTick,0.1);marqueeTick=0
 marqueePos=marqueePos+marqueeDirection*24*delta
 if marqueePos>=marqueeLimit then marqueePos=marqueeLimit;marqueeDirection=-1;marqueeWait=2
 elseif marqueePos<=0 then marqueePos=0;marqueeDirection=1;marqueeWait=2 end
 titleViewport:SetHorizontalScroll(0)
end)
local function applyOpacity()
 local hovered=false
 for _,b in ipairs(compactButtons) do
  if b.hovered then hovered=true end
  b:SetAlpha(b.hovered and 1 or opacity(db and db.compactButtonOpacity,0.2,1))
 end
 local textAlpha=hovered and 1 or opacity(db and db.compactTextOpacity,0.2,0.95)
 title:SetAlpha(textAlpha);compactTime:SetAlpha(textAlpha)
 compactBG:SetColorTexture(0.025,0.025,0.025,opacity(db and db.compactBackground,0,0.35))
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
local function updateTime()
 if not current then return end
 local duration=tracks[current].duration or 0;local elapsed=math.max(0,GetTime()-started)
 if duration>0 then
  timing:SetText("Elapsed "..clock(elapsed).."   |   Remaining -"..clock(duration-elapsed).."   |   Total "..clock(duration))
  compactTime:SetText(clock(elapsed).." / "..clock(duration));progress:SetValue(math.min(1,elapsed/duration))
 else
  timing:SetText("Elapsed "..clock(elapsed).."   |   Duration unknown: regenerate library or use Next")
  compactTime:SetText(clock(elapsed).." / --:--");progress:SetValue(0)
 end
end
refresh=function()
 FauxScrollFrame_Update(scroll,#filtered,9,24)
 local offset=FauxScrollFrame_GetOffset(scroll)
 for i,b in ipairs(rows) do
  local index=filtered[offset+i];b.track=index
  if index then
   local t=tracks[index];b.title:SetText((playing and current==index and "> " or "")..safe(label(t)))
   b.duration:SetText((t.duration or 0)>0 and clock(t.duration) or "--:--");b:Show()
  else b:Hide() end
 end
 now:SetText(current and ((playing and "Playing: " or "Stopped: ")..safe(label(tracks[current]))) or "Select a song to play.")
 setTitle(current and safe(label(tracks[current])) or "MaliMusicPlayer")
end
local function rebuild()
 wipe(filtered);local q=string.lower(search:GetText() or "")
 for i,t in ipairs(tracks) do if q=="" or string.find(string.lower(label(t)),q,1,true) then filtered[#filtered+1]=i end end
 FauxScrollFrame_SetOffset(scroll,0);if scroll.ScrollBar then scroll.ScrollBar:SetValue(0) end;refresh()
end
scroll:SetScript("OnVerticalScroll",function(self,offset) FauxScrollFrame_OnVerticalScroll(self,offset,24,refresh) end)
search:SetScript("OnTextChanged",rebuild)
local function stop()
 playing=false;stopHandle();StopMusic()
 timing:SetText("Stopped");compactTime:SetText("Stopped");progress:SetValue(0);refresh()
end
play=function(index)
 if not tracks[index] then say("No tracks. Run UpdateLibrary.cmd, then restart WoW.");return end
 if GetCVar("Sound_EnableAllSound")=="0" or GetCVar("Sound_EnableMusic")=="0" then say("Enable sound and Music in WoW's audio settings.");return end
 stopHandle();playing=false;PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg")
 local ok,handle=PlaySoundFile(tracks[index].path,"Music")
 current=index;selected=index
 if not ok or not handle then
  StopMusic();timing:SetText("Playback failed. Check the file path and restart WoW after adding audio.")
  compactTime:SetText("Playback failed");progress:SetValue(0);refresh();say("Could not start: "..safe(label(tracks[index])));return
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
button(library,"Previous",16,-405,88,function() advance(-1,false) end)
button(library,"Play",110,-405,70,function() play(selected) end)
button(library,"Stop",186,-405,70,stop)
button(library,"Next",262,-405,70,function() advance(1,false) end)
local shuffle=button(library,"Shuffle: Off",338,-405,120,function() if db then db.shuffle=not db.shuffle;sync() end end)
local repeatButton=button(library,"Repeat: Off",464,-405,130,function() if db then db.repeatTrack=not db.repeatTrack;sync() end end)
sync=function()
 shuffle:SetText(db and db.shuffle and "Shuffle: On" or "Shuffle: Off")
 repeatButton:SetText(db and db.repeatTrack and "Repeat: On" or "Repeat: Off")
end
local volumeLabel=font(f,"GameFontNormalSmall",18,-477,160)
local volume=CreateFrame("Slider",nil,f,"OptionsSliderTemplate")
volume:SetPoint("TOPLEFT",180,-475);volume:SetSize(310,16);volume:SetMinMaxValues(0,100);volume:SetValueStep(1)
if volume.SetObeyStepOnDrag then volume:SetObeyStepOnDrag(true) end
local updatingVolume=false
local function syncVolume()
 updatingVolume=true
 local v=(tonumber(GetCVar("Sound_MusicVolume")) or 0)*100
 volume:SetValue(v);volumeLabel:SetText("Music volume: "..math.floor(v+0.5).."%");updatingVolume=false
end
volume:SetScript("OnValueChanged",function(self,value)
 value=math.floor(value+0.5);volumeLabel:SetText("Music volume: "..value.."%")
 if not updatingVolume then SetCVar("Sound_MusicVolume",value/100) end
end)
f:SetScript("OnShow",syncVolume)
setCompact=function(enabled)
 if db then db.compactMode=enabled end
 if enabled then f:Hide();applyOpacity();compact:Show() else compact:Hide();f:Show() end
end
togglePlayer=function()
 if f:IsShown() or compact:IsShown() then f:Hide();compact:Hide()
 elseif db and db.compactMode then setCompact(true)
 else showTab("library");setCompact(false) end
end
button(f,"Compact",500,-474,92,function() setCompact(true) end)
iconButton(269,-4,"Interface/Buttons/UI-PlusButton-UP","Open full player",function() showTab("library");setCompact(false) end)
iconButton(218,-29,"Interface/Buttons/UI-SpellbookIcon-PrevPage-Up","Previous track",function() advance(-1,false) end)
iconButton(244,-29,nil,"Stop playback",stop)
iconButton(270,-29,"Interface/Buttons/UI-SpellbookIcon-NextPage-Up","Next track",function() advance(1,false) end)
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
font(settings,"GameFontNormal",20,-287,555):SetText("Commands / compact shortcuts")
local help=font(settings,"GameFontHighlightSmall",24,-309,555)
help:SetText("/mmp - Show / hide  |  /mmp full  |  /mmp compact\n/mmp play  |  stop  |  next  |  prev\nCompact title / background: left-drag to move; right-click for quick controls.\nMinimap: left-click toggles; right-click opens home; drag to reposition.")
help:SetSpacing(2)
font(settings,"GameFontNormal",20,-377,555):SetText("About")
font(settings,"GameFontHighlightSmall",24,-397,555):SetText("MaliMusicPlayer v0.7.2 Experimental - By Mali Gnosis, for Mali Gnosis.")
local quote=font(settings,"GameFontHighlightSmall",24,-420,555)
quote:SetWordWrap(false)
quote:SetText('"If I throw a dog a bone, I don\'t want to know if it tastes good or not." - Brick Top')
local quoteFont=quote:GetFont()
for size=11,8,-0.5 do quote:SetFont(quoteFont,size,"");if quote:GetStringWidth()<=555 then break end end
font(settings,"GameFontDisableSmall",24,-447,555):SetText("Released under the MIT License. See LICENSE.MD for details.")
showTab("library")
local menu=CreateFrame("Frame","MaliMusicPlayerQuickControls",compact)
menu:SetSize(244,256);menu:SetFrameStrata("DIALOG");menu:SetClampedToScreen(true);menu:EnableMouse(true);menu:Hide()
table.insert(UISpecialFrames,"MaliMusicPlayerQuickControls")
local menuBG=menu:CreateTexture(nil,"BACKGROUND");menuBG:SetAllPoints();menuBG:SetColorTexture(0.025,0.025,0.035,0.98)
font(menu,"GameFontNormal",10,-10,224):SetText("MaliMusicPlayer - Quick controls")
local menuTrack=font(menu,"GameFontHighlightSmall",10,-32,224);menuTrack:SetWordWrap(false)
local function action(y,text,fn)
 return button(menu,text,8,y,228,function() menu:Hide();fn() end)
end
action(-55,"Play / restart current track",function() play(current or selected) end)
action(-82,"Stop",stop)
action(-109,"Previous track",function() advance(-1,false) end)
action(-136,"Next track",function() advance(1,false) end)
local menuShuffle=action(-163,"Shuffle: Off",function() if db then db.shuffle=not db.shuffle;sync() end end)
local menuRepeat=action(-190,"Repeat: Off",function() if db then db.repeatTrack=not db.repeatTrack;sync() end end)
action(-217,"Open Settings / About",function() showTab("settings");setCompact(false) end)
local function toggleMenu()
 if menu:IsShown() then menu:Hide();return end
 menuTrack:SetText(current and safe(label(tracks[current])) or "No track selected")
 menuShuffle:SetText(db and db.shuffle and "Shuffle: On" or "Shuffle: Off")
 menuRepeat:SetText(db and db.repeatTrack and "Repeat: On" or "Repeat: Off")
 local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale()
 menu:ClearAllPoints();menu:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x/scale+8,y/scale+8);menu:Show()
 GameTooltip:Hide()
end
local away=0
menu:SetScript("OnShow",function() away=0 end)
menu:SetScript("OnUpdate",function(self,dt)
 if self:IsMouseOver() or compact:IsMouseOver() then away=0
 else away=away+dt;if away>0.6 then self:Hide() end end
end)
local function compactMouseDown(self,which)
 if which~="LeftButton" then return end
 menu:Hide();GameTooltip:Hide()
 if not compactMoving then compactMoving=true;compact:StartMoving() end
end
local function compactMouseUp(self,which)
 if which=="LeftButton" then finishCompactMove()
 elseif which=="RightButton" and not compactMoving then toggleMenu() end
end
for _,surface in ipairs({compact,titleViewport}) do
 surface:SetScript("OnMouseDown",compactMouseDown)
 surface:SetScript("OnMouseUp",compactMouseUp)
end
compact:HookScript("OnHide",function() finishCompactMove();menu:Hide();GameTooltip:Hide() end)

-- Standalone minimap launcher: no broker libraries, custom image or TOC edit.
local minimapButton
local function createMinimapButton()
 if minimapButton or not Minimap then return end
 local b=CreateFrame("Button","MaliMusicPlayerMinimapButton",Minimap)
 minimapButton=b
 b:SetSize(32,32);b:SetFrameStrata("MEDIUM");b:SetFrameLevel(Minimap:GetFrameLevel()+10)
 b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp");b:RegisterForDrag("LeftButton")
 local icon=b:CreateTexture(nil,"ARTWORK")
 icon:SetSize(20,20);icon:SetPoint("TOPLEFT",7,-5)
 icon:SetTexture("Interface/ICONS/ClassIcon_Warlock");icon:SetTexCoord(0.08,0.92,0.08,0.92)
 local border=b:CreateTexture(nil,"OVERLAY")
 border:SetSize(54,54);border:SetPoint("TOPLEFT");border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
 b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight","ADD")
 local angle=tonumber(db and db.minimapAngle) or 225
 local dragging,wasDragged=false,false
 local function position()
  local a=math.rad(angle)
  local rx=Minimap:GetWidth()/2+8
  local ry=Minimap:GetHeight()/2+8
  b:ClearAllPoints();b:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*rx,math.sin(a)*ry)
 end
 local function cursorAngle()
  local x,y=GetCursorPosition();local scale=Minimap:GetEffectiveScale()
  local cx,cy=Minimap:GetCenter();if not cx or not cy then return end
  local dx,dy=x/scale-cx,y/scale-cy
  if dx==0 and dy==0 then return end
  local a
  if dx==0 then a=dy>0 and math.pi/2 or -math.pi/2
  else
   a=math.atan(dy/dx)
   if dx<0 then a=a+math.pi end
  end
  angle=math.deg(a)%360;position()
 end
 local function finishDrag()
  if not dragging then return end
  dragging=false
  if db then db.minimapAngle=angle end
 end
 b:SetScript("OnMouseDown",function(self,which) if which=="LeftButton" then wasDragged=false end end)
 b:SetScript("OnDragStart",function() dragging=true;wasDragged=true;GameTooltip:Hide();cursorAngle() end)
 b:SetScript("OnDragStop",finishDrag)
 b:SetScript("OnMouseUp",function(self,which) if which=="LeftButton" then finishDrag() end end)
 b:SetScript("OnUpdate",function()
  if dragging then
   cursorAngle()
   if not IsMouseButtonDown("LeftButton") then finishDrag() end
  end
 end)
 b:SetScript("OnClick",function(self,which)
  if wasDragged then return end
  if which=="RightButton" then showTab("library");setCompact(false) else togglePlayer() end
 end)
 b:SetScript("OnEnter",function(self)
  if dragging then return end
  GameTooltip:SetOwner(self,"ANCHOR_LEFT");GameTooltip:SetText("MaliMusicPlayer")
  if current then GameTooltip:AddLine((playing and "Playing: " or "Stopped: ")..safe(label(tracks[current])),1,1,1,true) end
  GameTooltip:AddLine("Left-click: show / hide preferred view",0.75,0.85,1)
  GameTooltip:AddLine("Right-click: open home base",0.75,0.85,1)
  GameTooltip:AddLine("Left-drag: move around minimap",0.75,0.85,1)
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() GameTooltip:Hide() end)
 b:SetScript("OnHide",function() finishDrag();GameTooltip:Hide() end)
 Minimap:HookScript("OnSizeChanged",position)
 position();b:Show()
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
  db.compactBackground=opacity(db.compactBackground,0,0.35)
  db.compactTextOpacity=opacity(db.compactTextOpacity,0.2,0.95)
  db.compactButtonOpacity=opacity(db.compactButtonOpacity,0.2,1)
  restorePosition(f,"position");restorePosition(compact,"compactPosition")
  sync();rebuild();syncVolume();opacityInitializing=true
  backgroundSlider:SetValue(db.compactBackground*100);textSlider:SetValue(db.compactTextOpacity*100);buttonSlider:SetValue(db.compactButtonOpacity*100)
  opacityInitializing=false;applyOpacity()
  local unknown=0;for _,t in ipairs(tracks) do if (t.duration or 0)<=0 then unknown=unknown+1 end end
  say("v0.7.2 Experimental: "..#tracks.." tracks; "..unknown.." unknown durations. /mmp to open.")
 elseif event=="PLAYER_LOGIN" then registerOptionsPanel();createMinimapButton()
 elseif event=="LOADING_SCREEN_ENABLED" then loading=true
 elseif event=="LOADING_SCREEN_DISABLED" then
  loading=false
  if playing then updateTime();C_Timer.After(1,function() if playing and not loading then PlayMusic("Interface/AddOns/MaliMusicPlayer/Silence.ogg") end end) end
 elseif event=="CVAR_UPDATE" and f:IsShown() then syncVolume()
 elseif event=="PLAYER_LOGOUT" then stopHandle();playing=false;StopMusic() end
end)
local tick=0
events:SetScript("OnUpdate",function(self,elapsed)
 if not playing or loading then return end
 tick=tick+elapsed;if tick<0.2 then return end;tick=0
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
