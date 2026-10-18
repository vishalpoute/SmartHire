# Working agreements

Complete coherent, tested milestones toward the 2 November 2026 MVP target. The user removed daily commit quotas and minimum spacing on 18 October 2026. The user also removed work-hour restrictions on 18 October; work may proceed at any hour. Make useful commits as validation permits; never backdate, create empty activity commits or skip checks to meet a target.

Run `python scripts/work_window.py` at session start and before committing. The helper checks readable Git history; old randomized daily targets are no longer used. Avoid overlapping sessions in this checkout. Prioritize end-to-end acceptance criteria using docs/delivery-plan.md, and include security review in relevant milestones.

Use repository-local Git identity `Vishal Poute <159309295+vishalpoute@users.noreply.github.com>`. No co-author trailer is required. Do not claim the project was built without assistance.

Before committing, inspect the diff and staged files for secrets, run relevant checks, update the roadmap honestly, and use a specific commit message. Push to main only after checks pass. Preserve unrelated user changes. If a remote push fails, retry that commit without generating another one.

## Local Flutter launcher

On this Windows installation, the `flutter.bat` launcher stalled. The installed tool can be invoked directly:

```powershell
& 'C:/FLUTTER/flutter/bin/cache/dart-sdk/bin/dart.exe' --packages='C:/FLUTTER/flutter/packages/flutter_tools/.dart_tool/package_config.json' 'C:/FLUTTER/flutter/bin/cache/flutter_tools.snapshot' analyze
```

Use the same invocation with `pub get`, `test`, or `build web --release`. SDK cache access may require the existing Flutter execution approval. CI uses the standard Flutter commands.
