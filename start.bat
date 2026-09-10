@echo off
REM Starts backend (Spring Boot, :8080) and frontend (Angular dev server,
REM :4200) in the background, if they aren't already running. Safe to
REM re-run: skips a server whose port is already listening instead of
REM starting a second, conflicting instance.
REM
REM Usage: start.bat   (from cmd.exe, in this folder)

setlocal enabledelayedexpansion
set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%payroll-automation-backend"
set "FRONTEND_DIR=%ROOT%Payroll Automation"
set "LOGDIR=%ROOT%.devserver-logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM Small generated wrapper .cmd files, one per server - avoids nested-quote
REM breakage in `start ... cmd /c "cd /d "<path with spaces>" && ..."`,
REM which silently ate the `cd /d` on a path containing spaces (Payroll
REM Automation) and left mvnw.cmd unresolved.
> "%LOGDIR%\_run_backend.cmd" (
  echo @echo off
  echo cd /d "%BACKEND_DIR%"
  echo call .\mvnw.cmd -q -o spring-boot:run -Dspring-boot.run.profiles=dev ^> "%LOGDIR%\backend.log" 2^>^&1
)
> "%LOGDIR%\_run_frontend.cmd" (
  echo @echo off
  echo cd /d "%FRONTEND_DIR%"
  echo call npx ng serve --port 4200 ^> "%LOGDIR%\frontend.log" 2^>^&1
)

call :is_listening 8080
if "%FOUND%"=="1" (
  echo Backend already running on :8080 - skipping.
) else (
  echo Starting backend ^(mvnw spring-boot:run, profile dev^)...
  start "payroll-backend" /min cmd /c "%LOGDIR%\_run_backend.cmd"
  call :wait_for_port 8080 Backend
)

call :is_listening 4200
if "%FOUND%"=="1" (
  echo Frontend already running on :4200 - skipping.
) else (
  echo Starting frontend ^(ng serve, port 4200^)...
  start "payroll-frontend" /min cmd /c "%LOGDIR%\_run_frontend.cmd"
  call :wait_for_port 4200 Frontend
)

echo.
echo Open http://localhost:4200 - stop both with stop.bat
goto :eof

:is_listening
set "FOUND=0"
netstat -ano | findstr /R /C:":%1 .*LISTENING" >nul
if not errorlevel 1 set "FOUND=1"
goto :eof

:wait_for_port
set "PORT=%1"
set "LABEL=%2"
set /a TRIES=0
:wait_loop
call :is_listening %PORT%
if "%FOUND%"=="1" (
  echo %LABEL% up, log: %LOGDIR%\%LABEL%.log
  goto :eof
)
set /a TRIES+=1
if %TRIES% GEQ 60 (
  echo %LABEL% did not come up in 60s - check %LOGDIR%\%LABEL%.log
  goto :eof
)
timeout /t 1 /nobreak >nul
goto :wait_loop
