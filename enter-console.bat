@echo off
cls
echo Select which console to enter:
echo 1) Minecraft Server
echo 2) Hytale Server
echo 3) Playit Agent
set /p choice=Enter choice [1-3]: 

if "%choice%"=="1" goto minecraft
if "%choice%"=="2" goto hytale
if "%choice%"=="3" goto playit
echo Invalid choice.
pause
exit

:minecraft
echo Attaching to Minecraft Server... (Press Ctrl+P, Ctrl+Q to detach)
docker attach minecraft_server
goto end

:hytale
echo Attaching to Hytale Server... (Press Ctrl+P, Ctrl+Q to detach)
docker attach hytale_server
goto end

:playit
echo Attaching to Playit Agent... (Press Ctrl+P, Ctrl+Q to detach)
docker attach playit_agent
goto end

:end
pause
