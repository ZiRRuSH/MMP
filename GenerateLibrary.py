#!/usr/bin/env python3
"""Build MaliMusicPlayer's Library.lua from the MP3s in the mp3 folder.

Same job as GenerateLibrary.ps1, for macOS and Linux (works on Windows too).
Needs only Python 3.8 or newer; no packages to install.

Run it from anywhere:  python3 GenerateLibrary.py
"""
import os
import re
import shutil
import struct
import subprocess
import sys

# Your music and playlist live in a companion folder next to the add-on, so add-on
# updates (which replace the whole MaliMusicPlayer folder) never delete them.
HERE = os.path.dirname(os.path.abspath(__file__))
COMPANION = os.path.join(os.path.dirname(HERE), "MaliMusic")
MUSIC = os.path.join(COMPANION, "mp3")
OUTPUT = os.path.join(COMPANION, "Library.lua")
OLD_MUSIC = os.path.join(HERE, "mp3")
ADDON_PATH = "Interface/AddOns/MaliMusic/"

V1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
V2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]


# Duration: add up MPEG audio frames, exactly like GenerateLibrary.ps1.

def frame_header(data, p):
    """Return (frame length, seconds) for a Layer III frame header at p, or None."""
    if p + 4 > len(data) or data[p] != 0xFF or (data[p + 1] & 0xE0) != 0xE0:
        return None
    version, layer = (data[p + 1] >> 3) & 3, (data[p + 1] >> 1) & 3
    bitrate_index, rate_index = (data[p + 2] >> 4) & 15, (data[p + 2] >> 2) & 3
    if version == 1 or layer != 1 or bitrate_index in (0, 15) or rate_index == 3:
        return None
    rate = (44100, 48000, 32000)[rate_index]
    if version == 2:
        rate //= 2
    elif version == 0:
        rate //= 4
    bitrate = (V1 if version == 3 else V2)[bitrate_index] * 1000
    length = (144 if version == 3 else 72) * bitrate // rate + ((data[p + 2] >> 1) & 1)
    seconds = (1152 if version == 3 else 576) / rate
    return (length, seconds) if length >= 4 else None


def id3v2_size(data):
    if len(data) >= 10 and data[:3] == b"ID3":
        size = ((data[6] & 127) << 21) | ((data[7] & 127) << 14) | ((data[8] & 127) << 7) | (data[9] & 127)
        size += 10
        if data[3] == 4 and data[5] & 16:  # v2.4 footer
            size += 10
        return size
    return 0


def duration(data):
    p, total, frames, locked = id3v2_size(data), 0.0, 0, False
    end = len(data)
    while p + 4 <= end:
        header = frame_header(data, p)
        if header and p + header[0] <= end:
            if not locked:
                following = frame_header(data, p + header[0]) if p + header[0] + 4 <= end else None
                if not following:
                    p += 1
                    continue
            total += header[1]
            frames += 1
            p += header[0]
            locked = True
        else:
            locked = False
            p += 1
    return total if frames >= 2 else 0.0


# Tags: ID3v2 (2.2 / 2.3 / 2.4) title and artist, falling back to ID3v1.

def decode_text(raw):
    if not raw:
        return ""
    encoding, body = raw[0], raw[1:]
    try:
        if encoding == 0:
            text = body.decode("latin-1")
        elif encoding == 1:
            text = body.decode("utf-16")
        elif encoding == 2:
            text = body.decode("utf-16-be")
        else:
            text = body.decode("utf-8")
    except (UnicodeDecodeError, ValueError):
        text = body.decode("latin-1", "replace")
    # Multiple values are NUL-separated; Windows shows them joined with "; ".
    parts = [part.strip() for part in text.replace("\ufeff", "").split("\x00") if part.strip()]
    return "; ".join(parts)


def unsync(data):
    return data.replace(b"\xff\x00", b"\xff")


def id3v2_tags(data):
    tags = {}
    if len(data) < 10 or data[:3] != b"ID3":
        return tags
    major, flags = data[3], data[5]
    size = id3v2_size(data) - 10
    body = data[10:10 + size]
    if flags & 0x80 and major < 4:
        body = unsync(body)
    p = 0
    if flags & 0x40 and major >= 3 and len(body) >= 4:  # extended header
        if major == 4:
            p = ((body[0] & 127) << 21) | ((body[1] & 127) << 14) | ((body[2] & 127) << 7) | (body[3] & 127)
        else:
            p = struct.unpack(">I", body[:4])[0] + 4
    wanted = {"TIT2": "title", "TPE1": "artist", "TT2": "title", "TP1": "artist"}
    while p < len(body):
        if major == 2:
            if p + 6 > len(body) or body[p] == 0:
                break
            frame_id = body[p:p + 3].decode("latin-1", "replace")
            frame_size = (body[p + 3] << 16) | (body[p + 4] << 8) | body[p + 5]
            header, frame_flags = 6, 0
        else:
            if p + 10 > len(body) or body[p] == 0:
                break
            frame_id = body[p:p + 4].decode("latin-1", "replace")
            raw = body[p + 4:p + 8]
            if major == 4:
                frame_size = ((raw[0] & 127) << 21) | ((raw[1] & 127) << 14) | ((raw[2] & 127) << 7) | (raw[3] & 127)
            else:
                frame_size = struct.unpack(">I", raw)[0]
            header, frame_flags = 10, body[p + 9]
        content = body[p + header:p + header + frame_size]
        if major == 4 and frame_flags & 0x02:
            content = unsync(content)
        if frame_id in wanted and wanted[frame_id] not in tags:
            value = decode_text(content)
            if value:
                tags[wanted[frame_id]] = value
        p += header + frame_size
    return tags


def id3v1_tags(data):
    if len(data) >= 128 and data[-128:-125] == b"TAG":
        block = data[-128:]
        title = block[3:33].split(b"\x00")[0].decode("latin-1").strip()
        artist = block[33:63].split(b"\x00")[0].decode("latin-1").strip()
        return {key: value for key, value in (("title", title), ("artist", artist)) if value}
    return {}


def lua_string(text):
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
    return '"' + text + '"'


def seconds_text(value):
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return text or "0"


def move_old_music():
    """One-time move from the old location inside the add-on folder."""
    moved = 0
    if not os.path.isdir(OLD_MUSIC):
        return moved
    for root, _dirs, names in os.walk(OLD_MUSIC):
        for name in names:
            if name == "PUT_YOUR_MP3S_HERE.txt":
                continue
            source = os.path.join(root, name)
            target = os.path.join(MUSIC, os.path.relpath(source, OLD_MUSIC))
            if os.path.exists(target):
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.move(source, target)
            moved += 1
    return moved


def write_companion_toc():
    """The companion's .toc copies the add-on's Interface line so it is never flagged out of date."""
    interface = "## Interface: 16001"
    try:
        with open(os.path.join(HERE, "MaliMusicPlayer.toc"), encoding="utf-8-sig") as handle:
            for line in handle:
                if re.match(r"^## Interface:", line):
                    interface = line.strip()
                    break
    except OSError:
        pass
    lines = [interface,
             "## Title: MaliMusic",
             "## IconTexture: Interface\\AddOns\\MaliMusicPlayer\\media\\icon",
             "## Dependencies: MaliMusicPlayer",
             "## Group: MaliMusicPlayer",
             "## Category: Media",
             "## X-MaliMusic-Format: 2",
             "## Notes: Your MP3s and playlist for MaliMusicPlayer. No code, just your music. Keep it enabled so the player can find it.",
             "## Author: Mali Gnosis",
             "",
             "Library.lua"]
    with open(os.path.join(COMPANION, "MaliMusic.toc"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def open_folder(path):
    try:
        if sys.platform == "darwin":
            subprocess.Popen(["open", path])
        elif os.name == "nt":
            os.startfile(path)  # noqa: available on Windows only
        else:
            subprocess.Popen(["xdg-open", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def main():
    os.makedirs(MUSIC, exist_ok=True)
    moved = move_old_music()
    if moved:
        print(f"Moved {moved} file(s) from MaliMusicPlayer/mp3 to MaliMusic/mp3.")
    write_companion_toc()
    files = []
    for root, _dirs, names in os.walk(MUSIC):
        for name in names:
            if name.lower().endswith(".mp3"):
                files.append(os.path.join(root, name))
    files.sort(key=lambda path: path.lower())

    lines = ["-- Generated by MaliMusicPlayer GenerateLibrary.py; durations scanned from MP3 frames.",
             "MaliMusicPlayerLibrary = {"]
    failures = []
    for index, path in enumerate(files, 1):
        name = os.path.basename(path)
        print(f"[{index}/{len(files)}] {name}", flush=True)
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as error:
            print(f"  warning: could not read: {error}")
            failures.append(path)
            continue
        tags = id3v1_tags(data)
        tags.update(id3v2_tags(data))
        title = tags.get("title") or os.path.splitext(name)[0]
        artist = tags.get("artist", "")
        seconds = duration(data)
        if seconds <= 0:
            failures.append(path)
        relative = os.path.relpath(path, COMPANION).replace(os.sep, "/")
        lines.append("  {{ title={}, artist={}, path={}, duration={} }},".format(
            lua_string(title), lua_string(artist), lua_string(ADDON_PATH + relative), seconds_text(seconds)))
    lines.append("}")

    temp = OUTPUT + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    os.replace(temp, OUTPUT)

    print(f"Found: {len(files)} MP3s; durations detected: {len(files) - len(failures)}; failed: {len(failures)}")
    for path in failures:
        print(f"  warning: no duration: {path}")
    print(f"Library rebuilt in {COMPANION}")
    if not files:
        print(f"No MP3s yet. Put your music in: {MUSIC}")
        print("Then run the updater again.")
        open_folder(MUSIC)
    print("Restart WoW after adding audio; /reload is enough for duration/title changes.")
    print('In the AddOns list, keep "MaliMusic" enabled.')
    return 0


if __name__ == "__main__":
    sys.exit(main())
