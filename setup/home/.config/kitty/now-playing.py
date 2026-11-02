#!/usr/bin/env python3
# Now playing panel for kitty - shows current music track with album art

import subprocess

def get_now_playing():
    """Get currently playing track using playerctl or mpc"""
    # Try playerctl first (works with most players via DBus)
    try:
        result = subprocess.run(
            ['playerctl', 'metadata', '--format={{artist}} - {{title}}'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    
    # Fall back to mpc
    try:
        result = subprocess.run(
            ['mpc', 'current', '--format={{artist}} - {{title}}'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass
    
    return "No music playing"

def main():
    # Get the current track info
    track = get_now_playing()
    
    # Format the output
    if track and track != "No music playing":
        # Truncate if too long
        max_width = 60
        if len(track) > max_width:
            track = track[:max_width-3] + "..."
        print(track)
    else:
        print("No music playing")

if __name__ == '__main__':
    main()