@echo off
cd /d "%~dp0"

:: Check for admin privileges (needed for port reservation)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: After elevation, working directory resets to System32
cd /d "%~dp0"

:: Reserve TCP ports from Hyper-V dynamic exclusion ranges.
:: Without this, Windows may randomly claim ports Docker needs.
echo Reserving ports from Hyper-V...
net stop winnat >nul 2>&1
netsh int ipv4 add excludedportrange protocol=tcp startport=25565 numberofports=1 >nul 2>&1
net start winnat >nul 2>&1

docker compose up -d
echo Press Enter to exit...
pause >nul
