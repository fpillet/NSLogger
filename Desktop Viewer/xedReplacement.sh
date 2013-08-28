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
if isXcodeRunning() then
	locateCorrectXcodeWindow()
else
	-- using `do shell script` here instead of AppleScript's `open` command... 
	-- `open` seems to not default to last instance of Xcode used/preferences
	--  ↳ not good when you're using the Xcode Developer Previews
	do shell script "open $file"	
	--  ↳ "Open Quickly" doesn't seem to work in this scenario without ugly delay hacks...
end if

on isXcodeRunning()
	tell application "System Events"
		set isRunning to ((application processes whose (name is equal to "Xcode")) count)
	end tell
	if isRunning is greater than 0 then
		return true
	else
		return false
	end if
end isXcodeRunning

on locateCorrectXcodeWindow()
	set foundByName to false

	-- fastest method to detect proper window is by name
	tell application "System Events"
		set allXcodeWindowsByName to name of window of processes whose name is "Xcode"
		repeat with theWindowName in item 1 of allXcodeWindowsByName
			if theWindowName contains "$client" then
				tell process "Xcode"
					set frontmost to true
					perform action "AXRaise" of (windows whose title is theWindowName)
	            	click menu item "Open Quickly…" of menu 1 of menu bar item "File" of menu bar 1
	            	set value of (first text field of window 1 whose role description is "search text field") to "$output"
	            	keystroke return
	            	set foundByName to true
				end tell
			end if
		end repeat
	end tell	

	-- if can't find by name, have to loop through all windows to check project names
	if foundByName is false then
		tell application "Xcode"
			set allXcodeWindows to index of every window whose visible is true
			set totalWindows to count allXcodeWindows
			set windowCounter to totalWindows
			repeat while windowCounter is not equal to 0
				tell application "System Events"
					tell process "Xcode"
						set frontmost to true
						perform action "AXRaise" of window totalWindows
						set windowCounter to (windowCounter - 1)
					end tell
				end tell
				set projectDirectory to (get project directory of first project)
				if "$file" contains projectDirectory then					
					my enterOpenQuicklyText()
					set windowCounter to 0
				end if
			end repeat
		end tell
	end if
end locateCorrectXcodeWindow

on enterOpenQuicklyText()
	tell application "System Events"
		tell process "Xcode"
			click menu item "Open Quickly…" of menu 1 of menu bar item "File" of menu bar 1
			set value of (first text field of window 1 whose role description is "search text field") to "$output"
			keystroke return
		end tell
	end tell
end enterOpenQuicklyText
EOF