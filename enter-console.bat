@echo off
cls
echo Select which console to enter:
echo 1) Minecraft Server
echo 2) Hytale Server
echo 3) Playit Agent
echo 4) Ark: Survival Evolved Server
echo 5) Ark: Survival Ascended Server
set /p choice=Enter choice [1-5]: 

if "%choice%"=="1" goto minecraft
if "%choice%"=="2" goto hytale
if "%choice%"=="3" goto playit
if "%choice%"=="4" goto ark_ase
if "%choice%"=="5" goto ark_asa
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

:ark_ase
echo Attaching to Ark: Survival Evolved Server... (Press Ctrl+P, Ctrl+Q to detach)
docker attach ark_ase_server
goto end

:ark_asa
echo Attaching to Ark: Survival Ascended Server... (Press Ctrl+P, Ctrl+Q to detach)
docker attach ark_asa_server
goto end

:end
pause
