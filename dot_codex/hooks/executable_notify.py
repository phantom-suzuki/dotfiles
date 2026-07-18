#!/usr/bin/env python3
"""Claude Code hook: macOS sound notifications."""
import json, subprocess, sys, os

SOUNDS = {
    "Stop":         "/System/Library/Sounds/Glass.aiff",
    "Notification": "/System/Library/Sounds/Ping.aiff",
    "PreCompact":   "/System/Library/Sounds/Sosumi.aiff",
}

def main():
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        return

    event = data.get("hook_event_name", "")
    sound = SOUNDS.get(event)
    if sound and os.path.exists(sound):
        subprocess.Popen(
            ["afplay", sound],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

if __name__ == "__main__":
    main()
