(*
Quick Note for Alter (https://alterhq.com)

Set this as a quick action to quickly send chat results to a new note
that already uses your preferred template structure via Ursus CLI.
*)

on run argv
	if (count of argv) is 0 then
		error "Missing content argument."
	end if
	
	set noteContent to item 1 of argv
	set homePath to POSIX path of (path to home folder)
	set cliPath to homePath & ".local/bin/ursus"
	
	do shell script quoted form of cliPath & " --new-note -on -nw -c " & quoted form of noteContent
end run
