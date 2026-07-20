@echo off
cd /d C:\Users\ertyui\ZCodeProject\nusa_kasir
call C:\Users\ertyui\flutter\bin\flutter.bat build apk --release > C:\Users\ertyui\ZCodeProject\nusa_kasir\build_apk_log.txt 2>&1
if exist build\app\outputs\flutter-apk\app-release.apk (
  copy /Y build\app\outputs\flutter-apk\app-release.apk C:\Users\ertyui\ZCodeProject\nusa_kasir\release_apk.apk
) else (
  for /r %%f in (app-release.apk) do copy /Y "%%f" C:\Users\ertyui\ZCodeProject\nusa_kasir\release_apk.apk
)
echo BUILD_DONE > C:\Users\ertyui\ZCodeProject\nusa_kasir\build_done.txt
