# Spike 009 run sheet (throwaway)

Answers ticket 009 plus spec 005 §12 Q2, Q4, Q6. Record every command's output in RESULTS.md.
App binary: `A=/Applications/TidySpike.app/Contents/MacOS/TidySpike`

1. `security find-identity -v -p codesigning` → pick the "Apple Development: …" identity (Personal Team). None? Stop: John opens Xcode > Settings > Accounts > Manage Certificates > + Apple Development.
2. `./build.sh "<identity>"` (records cert dates = Q6), then `sudo rm -rf /Applications/TidySpike.app; cp -R build/TidySpike.app /Applications/`. `sudo` may not work; then ditto to ~/Applications instead.
3. `$A register` → expect requiresApproval. `$A settings`; John turns on TidySpike under "Allow in the Background". `$A status` → enabled.
4. `$A call` → want `uid=0`, a written proof file, and the probes. Note FDA probe result (no FDA granted yet).
5. Q2: John adds /Applications/TidySpike.app to Privacy & Security > Full Disk Access. `$A call` again. If still DENIED, add `TidySpike.app/Contents/MacOS/TidySpikeHelper` by hand, `sudo launchctl kickstart -k system/com.tidymymac.spike.helper` (or unregister/register), `$A call`.
6. Rebuild survival: edit nothing, `./build.sh "<identity>"`, copy over the installed app again, `$A status`, `$A call`. Did it still work without re-approval?
7. Optional comparison: `./build.sh -` (ad hoc), reinstall, status + call.
8. Cleanup: `$A unregister`, remove the app, FDA entries, and `/Library/Application Support/TidyMyMacSpike` (needs admin; John can do it in Finder).
Debug: `sfltool dumpbtm | grep -A20 tidymymac`, `log show --last 5m --predicate 'subsystem == "com.apple.xpc.launchd"' | grep tidymymac`.
