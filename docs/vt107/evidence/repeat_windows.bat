@echo off
setlocal enabledelayedexpansion
set GODOT="C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set RUNS=10
pushd "%~dp0..\..\.."
set ROOT=%CD%
set OUT=%ROOT%\docs\vt107\evidence\win_08_repeat10_slice5.log
set TMPLOG=%TEMP%\vt107_repeat_run.log
git rev-parse HEAD > "%OUT%"
%GODOT% --version >> "%OUT%"
echo Windows, %RUNS% consecutive full-suite runs >> "%OUT%"
set FAILS=0
cd procedural-dungeon
for /L %%i in (1,1,%RUNS%) do (
    %GODOT% --headless --path . -s res://tests/run_tests.gd > "%TMPLOG%" 2>&1
    set RC=!ERRORLEVEL!
    if not "!RC!"=="0" set /a FAILS+=1
    echo run %%i: exit !RC! >> "%OUT%"
    findstr /C:"tests," /C:"TC-18" "%TMPLOG%" >> "%OUT%"
)
echo runs with a non-zero exit code: !FAILS! of %RUNS% >> "%OUT%"
cd ..
popd
type "%OUT%"
endlocal