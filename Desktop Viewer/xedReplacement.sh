#!/bin/bash

if [ "$1" = "-l" ] || [ "$1" = "--line" ] ; then
    line=$2
    file=$3
else
    line=1
    file=$1
fi

echo -n "${file##*/}:$line" | pbcopy

osascript &>/dev/null <<EOF
    tell application "Xcode"
        activate
        tell application "System Events"
            keystroke "o" using {command down, shift down}
            keystroke "v" using {command down}
            keystroke return
        end tell
    end tell
EOF
