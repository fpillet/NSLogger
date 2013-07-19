#!/bin/bash

if [ "$1" = "-l" ] || [ "$1" = "--line" ] ; then
    line=$2
    file=$3
    client=$4
else
    line=1
    file=$1
fi

echo -n "${file##*/}:$line" | pbcopy

osascript &>/dev/null <<EOF
tell application "System Events"
	set allWindowsName to name of window of processes whose name is "Xcode"
	repeat with theWindowName in item 1 of allWindowsName
		if theWindowName contains "$client" then
			tell process "Xcode"
				set frontmost to true
				perform action "AXRaise" of (windows whose title is theWindowName)
				keystroke "o" using {command down} -- default is actually keystroke "o" using {command down, shift down}
                keystroke "v" using {command down}
                keystroke return
			end tell
		end if
	end repeat
end tell
EOF