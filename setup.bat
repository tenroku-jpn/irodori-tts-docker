@echo off
setlocal
 
echo ============================================
echo   Irodori-TTS ROCm Auto Setup (WSL2 + Radeon)
echo ============================================
echo.
 
REM =========================================================
REM 1. WSL Check (Ubuntu-24.04 required)
REM =========================================================
 
wsl -d %DISTRO% -- uname -a >nul 2>&1
 
if errorlevel 1 (
    echo [ERROR] %DISTRO% not found in installed WSL distributions.
    echo Installed distros:
    wsl -l -v
    pause
    exit /b 1
)
 
echo [OK] Ubuntu-24.04 detected.
echo.
 
REM =========================================================
REM 2. Windows SDK Check
REM =========================================================
 
set "SDK_PATH=C:\PROGRA~2\Windows Kits\10\Include\10.0.26100.0"
 
if not exist "%SDK_PATH%" (
    echo [ERROR] Windows SDK not found.
    echo Required path:
    echo %SDK_PATH%
    pause
    exit /b 1
)
 
echo [OK] Windows SDK detected.
echo.
 
REM =========================================================
REM 3. Docker Desktop Check
REM =========================================================
 
docker --version >nul 2>&1
 
if errorlevel 1 (
    echo [ERROR] Docker Desktop not found.
    echo Install Docker Desktop:
    echo https://www.docker.com/products/docker-desktop/
    pause
    exit /b 1
)
 
echo [OK] Docker Desktop detected.
echo.
 
REM =========================================================
REM 4. Apply WSL2 VM Optimization (.wslconfig)
REM =========================================================
 
(
echo [wsl2]
echo memory=16GB
echo processors=8
echo swap=0
echo localhostForwarding=true
) > "%USERPROFILE%\.wslconfig"
 
echo [OK] .wslconfig applied.
echo.
 
REM =========================================================
REM 5. Execute Setup in WSL
REM =========================================================
 
wsl -d %DISTRO% -- bash -c "mkdir -p ~/docker"
wsl -d %DISTRO% -- bash -c "if [ ! -d ~/docker/irodori-tts-docker ]; then git clone https://github.com/tenroku-jpn/irodori-tts-docker.git ~/docker/irodori-tts-docker; fi"
 
wsl -d %DISTRO% -- bash ~/docker/irodori-tts-docker/setup.sh
 
echo.
echo ============================================
echo   Setup Complete!
echo ============================================
echo.
echo Web UI:
echo   http://localhost:7860
echo.
echo VoiceDesign UI:
echo   http://localhost:7861
echo.
echo API Server (OpenAI Compatible):
echo   http://localhost:8088/v1/audio/speech
echo.
pause
exit /b 0
