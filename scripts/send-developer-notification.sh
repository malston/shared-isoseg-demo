#!/usr/bin/env bash
# ABOUTME: Sends platform notification to the Developer iTerm window
# ABOUTME: Used during demo recording to simulate operator-to-developer communication

osascript << 'APPLESCRIPT'
tell application "iTerm"
    repeat with w in windows
        if name of w contains "Developer" then
            tell first session of first tab of w
                write text "./scripts/show-notification.sh"
            end tell
            return "Sent to: " & name of w
        end if
    end repeat
    return "ERROR: No window found with 'Developer' in the name"
end tell
APPLESCRIPT
