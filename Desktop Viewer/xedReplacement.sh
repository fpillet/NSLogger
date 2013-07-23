#!/bin/bash

if [ "$1" = "-l" ] || [ "$1" = "--line" ] ; then
    line=$2
    file=$3
    client=$4
else
    line=1
    file=$1
fi

output=`echo -n "${file##*/}:$line"`

osascript &>/dev/null <<EOF
tell application "System Events"
	set allWindowsName to name of window of processes whose name is "Xcode"
	repeat with theWindowName in item 1 of allWindowsName
		if theWindowName contains "$client" then
			tell process "Xcode"
				set frontmost to true
				perform action "AXRaise" of (windows whose title is theWindowName)
                click menu item "Open Quickly…" of menu 1 of menu bar item "File" of menu bar 1
                set value of (first text field of window 1 whose role description is "search text field") to "$output"
                keystroke return
			end tell
		end if
	end repeat
end tell
EOF