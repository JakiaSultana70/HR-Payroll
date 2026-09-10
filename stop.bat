@echo off
REM Stops the backend (:8080) and frontend (:4200) dev servers. Kills by
REM whatever process actually owns each port right now - mvnw/npx spawn
REM child processes that hold the real listening socket, so that's the
REM reliable way to find them.
REM
REM Usage: stop.bat

setlocal enabledelayedexpansion

call :stop_port 8080 Backend
call :stop_port 4200 Frontend

timeout /t 1 /nobreak >nul

set "STILL_UP=0"
netstat -ano | findstr /R /C:":8080 .*LISTENING" >nul && set "STILL_UP=1"
netstat -ano | findstr /R /C:":4200 .*LISTENING" >nul && set "STILL_UP=1"
if "%STILL_UP%"=="1" (
  echo Still listening, may need another run or a manual kill:
  netstat -ano | findstr /R /C:":8080 .*LISTENING" /C:":4200 .*LISTENING"
) else (
  echo Both stopped.
)

set "ROOT=%~dp0"
if exist "%ROOT%.devserver-pids.json" del "%ROOT%.devserver-pids.json"
goto :eof

:stop_port
set "PORT=%1"
set "LABEL=%2"
set "ANY=0"
REM A single process (e.g. the JVM) often listens on both the IPv4 and
REM IPv6 form of the same port - dedupe so it's only killed once instead
REM of a second, no-op taskkill against an already-dead pid.
set "SEEN="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
  echo !SEEN! | findstr /C:" %%P " >nul
  if errorlevel 1 (
    set "SEEN=!SEEN! %%P "
    echo Stopping %LABEL% ^(:%PORT%^) - pid %%P
    taskkill /F /PID %%P >nul 2>&1
    set "ANY=1"
  )
)
if "%ANY%"=="0" echo %LABEL% ^(:%PORT%^) - not running.
goto :eof
