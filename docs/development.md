# Working agreements

Continue through the roadmap in coherent, tested increments. Use randomized sessions between 9 AM and 6 PM Asia/Kolkata. Target six to seven useful commits per day, with a maximum of seven. Keep at least 60 minutes between actual commit timestamps; the helper persists randomized targets with 60–80 minute gaps and a first session between 9:00 and 9:40 AM. Do not commit at or after 6 PM. Validation may reduce the daily total. Never backdate, create empty activity commits, or skip checks to meet a quota.

Run `python scripts/work_window.py` before starting a scheduled session and again before committing. It reads Git history and persists randomized session targets in ignored local state. When not due, leave the repository alone. Do not run concurrent sessions in this checkout.

Use repository-local Git identity `Vishal Poute <159309295+vishalpoute@users.noreply.github.com>`. No co-author trailer is required. Do not claim the project was built without assistance.

Before committing, inspect the diff and staged files for secrets, run relevant checks, update the roadmap honestly, and use a specific commit message. Push to main only after checks pass. Preserve unrelated user changes. If a remote push fails, retry that commit without generating another one.

## Local Flutter launcher

On this Windows installation, the `flutter.bat` launcher stalled. The installed tool can be invoked directly:

```powershell
& 'C:/FLUTTER/flutter/bin/cache/dart-sdk/bin/dart.exe' --packages='C:/FLUTTER/flutter/packages/flutter_tools/.dart_tool/package_config.json' 'C:/FLUTTER/flutter/bin/cache/flutter_tools.snapshot' analyze
```

Use the same invocation with `pub get`, `test`, or `build web --release`. SDK cache access may require the existing Flutter execution approval. CI uses the standard Flutter commands.
