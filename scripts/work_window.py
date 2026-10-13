"""Choose real development windows; never modify Git timestamps."""

import json
import random
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IST = timezone(timedelta(hours=5, minutes=30))


def evaluate(now=None):
    now = now or datetime.now(IST)
    state_dir = ROOT / '.work-state'
    state_dir.mkdir(exist_ok=True)
    state_path = state_dir / f'{now.date()}.json'
    if state_path.exists():
        plan = json.loads(state_path.read_text())
    else:
        rng = random.SystemRandom()
        first = now.replace(hour=12, minute=0, second=0, microsecond=0)
        first += timedelta(minutes=rng.randrange(0, 121, 10))
        plan = {'first_session': first.isoformat(),
                'gaps_minutes': [rng.randrange(120, 161, 10) for _ in range(2)]}
        state_path.write_text(json.dumps(plan, indent=2))
    result = subprocess.run(
        ['git', 'log', '--format=%cI', '-20'], cwd=ROOT,
        capture_output=True, text=True, check=False,
    )
    commits = sorted(datetime.fromisoformat(line).astimezone(IST)
                     for line in result.stdout.splitlines() if line.strip())
    today = [commit for commit in commits if commit.date() == now.date()]
    if len(today) >= 3:
        return {'due': False, 'reason': 'daily_limit', 'commits_today': len(today)}
    target = datetime.fromisoformat(plan['first_session'])
    if today:
        target = today[-1] + timedelta(minutes=plan['gaps_minutes'][len(today) - 1])
    if commits:
        target = max(target, commits[-1] + timedelta(hours=2))
    in_window = 12 <= now.hour < 21
    return {'due': in_window and now >= target, 'commits_today': len(today),
            'next_target_ist': target.isoformat(),
            'reason': 'ready' if in_window and now >= target else 'wait'}


if __name__ == '__main__':
    print(json.dumps(evaluate()))
