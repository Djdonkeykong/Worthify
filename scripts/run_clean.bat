@echo off
flutter run --dart-define-from-file=.env -d emulator-5554 2>&1 | findstr /v "ImageReader_JNI"