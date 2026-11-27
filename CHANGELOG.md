# 📜 Changelog

## 🧩 1.2.1 — Family style

- **Settings is just settings now.** The About section is gone, and the tab is grouped into **Compact player**, **Full player** and **Sound**.
- **Flat sliders and checkboxes** on the Settings tab, in your theme's colors, to match the rest of the player.
- **Shared Mali Style.** MaliMusicPlayer now uses the same style code as the other Mali add-ons. Your colors and saved profiles carry over on their own.
- **Shuffle and Repeat** now light up their icon when they're on.

## 🔮 1.2 — Soulstone

- **All Mali, all the time.** The Classic look is retired, so every part of the player now uses Mali Style. If you were on Classic, you'll land in Mali Style with your colors and profiles intact.
- **Soulstone is the new default.** Fresh installs and **Restore default colors** now give you Soulstone's shadow purple. The original Mali colors are still a preset in the dropdown.
- **Song titles in Chinese, Japanese or Korean** now show up properly. Inter doesn't include those characters, so those titles switch to WoW's own font automatically. Korean and Chinese game clients use WoW's font throughout.
- **Crisper lines.** A bug kept 1px borders from snapping to exact screen pixels; they now stay sharp at any UI scale.
- The Flavor tab is shorter now that the UI style option is gone, and the color dropdown is a little more reliable.

## 🌈 1.1 — Themes

- **Redesigned Flavor tab:** UI style and color profiles are now tidy dropdown menus, and the six color swatches sit in a compact grid.
- **12 color presets**, each with its own vibe: Mali, Jazz 92, Soulstone, Fel, Terminal, Amber CRT, Rave 99, Trance State, Midnight, Ember, Graphite and Rosewater. Shadowflame, Arcane and Gilded are retired; any profiles you saved are untouched.
- **Profiles in one menu:** presets and your saved profiles share a single dropdown, each with a color chip so you can tell them apart. Hover one of your profiles and click the red × to delete it (you'll be asked to confirm first). **Save as...** names and saves your current colors.
- Mali Style now always uses the Inter font; Classic keeps the WoW font.
- **AddOns list fix:** MaliMusicPlayer now lives under **Media**, with your MaliMusic folder tucked underneath it. Run the library updater once after updating to apply it.
- If MaliMusic is enabled but your playlist didn't load, the player no longer says the folder is turned off.

## 🎨 1.0.3

- **Color presets** on the Flavor tab: Mali, Fel, Shadowflame, Arcane and Gilded.
- **Save your own color profiles:** name your current colors and save them, then load or delete them any time. Profiles are shared across all your characters.
- **Live compact preview:** the compact player shows up while you're on the Settings or Flavor tab, so you can see your changes as you make them.
- Fixed the track list jumping back to the top when hovering the search box.
- If your MaliMusic folder is from an older version, you'll get a one-time tip at login to run the library updater so it sits under MaliMusicPlayer in the AddOns list.

## 🧹 1.0.2

- **Tidier AddOns list:** **MaliMusic** now shows with the MaliMusicPlayer icon, nested under **MaliMusicPlayer** instead of the other way around. Run the library updater once after updating to refresh your MaliMusic folder.
- Your playlist now loads at login, so it works whatever order the game loads the two folders in.
- Game Music: removed an odd **Arathi Basin** entry that only held a shared Felwood theme used by one building there. Battleground music is under **Battlegrounds & Events › Battlegrounds**.

## 🛡️ 1.0.1 — Your music is safe from updates

**Your music and playlist now live in their own folder: `Interface/AddOns/MaliMusic`.**
Add-on managers like the CurseForge app replace the whole add-on folder when they update it, which wiped any music kept inside `MaliMusicPlayer/mp3`. From this version on, your music lives in `MaliMusic`, which updates never touch.

### ⚠️ Updating to this version

Because the old music folder was inside the add-on, **this update deletes it one last time**. If you can, back up `MaliMusicPlayer/mp3` before updating. Then:

1. Put your MP3s in `Interface/AddOns/MaliMusic/mp3` (create the `MaliMusic` and `mp3` folders if they aren't there yet).
2. Run the library updater in the `MaliMusicPlayer` folder (`UpdateLibrary.cmd` on Windows, `UpdateLibrary.command` on Mac, `UpdateLibrary.sh` on Linux).
3. Restart WoW and make sure **MaliMusic** is enabled in the AddOns list.

You only do this once. Future updates leave your music and playlist alone.

### 🔧 Changes

- 🛡️ Music and playlist moved to the new `MaliMusic` folder, safe from add-on updates.
- 📦 Updating by hand instead? The updater moves music from the old `MaliMusicPlayer/mp3` folder for you.
- 🩹 Fixed the `Error loading MaliMusicPlayer/Library.lua` warning after installing or updating.
- 💬 The Library tab now tells you what to do if your music folder is missing, turned off or out of date.
- 🗺️ Game Music is marked as WoW Forever only for now; other game versions show a note on the tab, and the MP3 player works everywhere.

## 🎉 1.0 — The big one

MaliMusicPlayer grows up: a brand new look, the game's own soundtrack at your fingertips, and an updater for every platform.

### 🗺️ Game Music

- **New Game Music tab** with all 435 of the game's music tracks, ready to play. *(WoW Forever for now; other game versions show a note on the tab, and the MP3 player works everywhere.)*
- Everything is sorted into a tree that's easy to browse: **Capitals**, **World Zones**, **Dungeons & Raids**, **Taverns & Inns**, **Battlegrounds & Events**, and **Moments & Stingers**.
- Zone intros and little musical stingers are filed with the places they belong to.
- Previous, Next, Shuffle and Repeat stay inside the place you're listening to, like a small playlist.
- Track lengths are learned the first time each one plays through, and remembered.
- `/mmp game` jumps straight to the tab.

### 🎨 UI overhaul

- **New default look: Mali Style.** Flat, dark and clean, with line icons, a now-playing panel, a progress line and a proper transport bar.
- **Classic is still here.** Prefer the standard Blizzard look? Switch to it anytime from the new **Flavor** tab.
- **Flavor tab:** pick your style, choose Inter or WoW's own font, and set your own colors, with a one-click **Restore default colors**.
- **Resizable main window**, with the list showing as many tracks as fit.
- **Redesigned compact player:** icon buttons, a progress line along the bottom, and a corner grip to drag its width (the width slider is gone).
- **Search** now finds tracks, places and categories, and opens everything that matches.
- **Settings, Flavor and Help scroll** when the window is short.
- **New add-on icon** for the AddOns list and minimap button.

### 💿 Your library

- **Mac and Linux support:** new `GenerateLibrary.py` plus double-click launchers (`UpdateLibrary.command` for macOS, `UpdateLibrary.sh` for Linux). Windows keeps `UpdateLibrary.cmd`.
- Previous now walks back through what you actually played.
- Your selected track, game or MP3, is remembered between sessions.

### 🛠️ Fixes and polish

- **Music off is easy to spot:** the music button turns red, with one clear message to turn music on instead of repeated warnings.
- Clearer messages when sound is off, volume is at 0%, or a track can't be found.
- The playing track is now marked with a speaker icon instead of `>`.
- Sharper 1px lines at any UI scale.
- New defaults for fresh installs; your existing settings carry over.
- `/mmpdiag dump` shows recent audio events to help with bug reports.

### 💜 Credits

Game data thanks to [wago.tools](https://wago.tools). Mali Style uses the [Inter](https://github.com/rsms/inter) font, included under the SIL Open Font License.

---

## 0.8.9

Previous stable release: MP3 library player with full and compact views.
