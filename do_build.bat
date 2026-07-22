@echo off
cd /d C:\Users\ertyui\ZCodeProject\nusa_kasir
del /q release_apk.apk build_done.txt 2>nul
call C:\Users\ertyui\flutter\bin\flutter.bat build apk --release > build_apk_log.txt 2>&1
if exist build\app\outputs\flutter-apk\app-release.apk (
  copy /Y build\app\outputs\flutter-apk\app-release.apk release_apk.apk >nul
) else (
  for /r %%f in (app-release.apk) do copy /Y "%%f" release_apk.apk >nul
)
echo BUILD_DONE > build_done.txt
