@echo off
echo.
echo =========================================
echo    🚀 Starting Worthify Flutter App
echo =========================================
echo.

REM Navigate to project directory
cd /d "D:\Worthify"

REM Check if emulator is running
echo 📱 Checking for running emulator...
"C:\Users\bestk\AppData\Local\Android\Sdk\platform-tools\adb.exe" devices | findstr emulator-5554 >nul
if %errorlevel% neq 0 (
    echo ❌ Emulator not found. Please start your Android emulator first.
    echo.
    echo To start emulator manually:
    echo 1. Open Android Studio
    echo 2. Go to Tools ^> AVD Manager
    echo 3. Start your emulator
    echo.
    pause
    exit /b 1
)

echo ✅ Emulator found: emulator-5554
echo.

REM Get dependencies
echo 📦 Getting Flutter dependencies...
flutter pub get
if %errorlevel% neq 0 (
    echo ❌ Failed to get dependencies
    pause
    exit /b 1
)

echo.
echo 🎨 Starting app with new design system...
echo    - Dark theme with golden accents
echo    - Bottom navigation with IndexedStack
echo    - Primary: #1c1c25 (Dark Navy)
echo    - Secondary: #fec948 (Golden Yellow)
echo.

REM Run the app
flutter run --dart-define-from-file=.env -d emulator-5554

echo.
echo 🏁 App session ended
pause