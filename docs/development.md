# Working agreements

Continue through the roadmap in coherent, tested increments. Daily sessions may vary between noon and 9 PM IST. Aim for three useful commits, allow two when time or verification limits progress, and never exceed three. Keep at least two hours between actual commit timestamps and aim for two to three hours. Never backdate, create empty activity commits, or skip checks to meet a quota.

Run `python scripts/work_window.py` before starting a scheduled session and again before committing. It reads Git history and persists randomized session targets in ignored local state. When not due, leave the repository alone. Do not run concurrent sessions in this checkout.

Use repository-local Git identity `Vishal Poute <159309295+vishalpoute@users.noreply.github.com>`. No co-author trailer is required. Do not claim the project was built without assistance.

Before committing, inspect the diff and staged files for secrets, run relevant checks, update the roadmap honestly, and use a specific commit message. Push to main only after checks pass. Preserve unrelated user changes. If a remote push fails, retry that commit without generating another one.

## Local Flutter launcher

On this Windows installation, the `flutter.bat` launcher stalled. The installed tool can be invoked directly:

```powershell
& 'C:/FLUTTER/flutter/bin/cache/dart-sdk/bin/dart.exe' --packages='C:/FLUTTER/flutter/packages/flutter_tools/.dart_tool/package_config.json' 'C:/FLUTTER/flutter/bin/cache/flutter_tools.snapshot' analyze
```

Use the same invocation with `pub get`, `test`, or `build web --release`. SDK cache access may require the existing Flutter execution approval. CI uses the standard Flutter commands.
