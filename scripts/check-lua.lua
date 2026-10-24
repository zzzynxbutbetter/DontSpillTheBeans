-- Used by check-lua.ps1: exits 1 and prints the error if the file in arg[1] does not parse.
local f, err = loadfile(arg[1])
if not f then io.stderr:write(err, "\n") os.exit(1) end
