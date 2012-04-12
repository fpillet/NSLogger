#!/bin/bash

if [ "$1" = "-l" ] || [ "$1" = "--line" ] ; then
    line=$2
    file=$3
else
    line=1
    file=$1
fi

osascript &>/dev/null <<EOF
    tell application "Xcode"
        open "$file"
        activate
        tell application "System Events"
            tell process "Xcode"
                keystroke "l" using command down
                repeat until window "Jump" exists
                end repeat
                click text field 1 of window "Jump"
                set value of text field 1 of window "Jump" to "$line"
                keystroke return
            end tell
        end tell
    end tell
EOF