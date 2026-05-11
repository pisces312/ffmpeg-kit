@echo off
setlocal

set BASEDIR=D:\nili\3rd_party_projects\ffmpeg-kit
set ANDROID_HOME=D:\nili\dev\android_sdk
set JAVA_HOME=D:\nili\dev\AndroidStudio\jbr

echo ==========================================
echo  Building AAR with Gradle (Windows)
echo ==========================================

cd /d "%BASEDIR%\android"

if "%FORCE%"=="1" (
    echo FORCE rebuild requested
    goto :build
)

if exist "%BASEDIR%\android\ffmpeg-kit-android-lib\build\outputs\aar\ffmpeg-kit-release.aar" (
    echo AAR already built, skipping
    echo Use FORCE=1 to rebuild
    goto :end
)

:build
echo Running Gradle...
call "%BASEDIR%\android\gradlew.bat" ffmpeg-kit-android-lib:assembleRelease

if errorlevel 1 (
    echo BUILD FAILED
    exit /b 1
)

echo.
echo ==========================================
echo  Build complete!
echo  AAR location:
dir /b "%BASEDIR%\android\ffmpeg-kit-android-lib\build\outputs\aar\*.aar"
echo ==========================================

:end
endlocal
