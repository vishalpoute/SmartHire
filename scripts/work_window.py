"""Check the user's work hours; commits have no quota or minimum spacing."""
import json
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IST = timezone(timedelta(hours=5, minutes=30))


def evaluate(now=None):
    now = (now or datetime.now(IST)).astimezone(IST)
    result = subprocess.run(
        ['git', 'log', '--format=%cI'], cwd=ROOT,
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        return {'due': False, 'reason': 'git_history_unavailable'}
    try:
        commits = [datetime.fromisoformat(line).astimezone(IST)
                   for line in result.stdout.splitlines() if line.strip()]
    except ValueError:
        return {'due': False, 'reason': 'git_history_unavailable'}
    in_window = 9 <= now.hour < 18
    return {'due': in_window,
            'commits_today': sum(commit.date() == now.date() for commit in commits),
            'reason': 'ready' if in_window else 'outside_work_hours'}


if __name__ == '__main__':
    print(json.dumps(evaluate()))
