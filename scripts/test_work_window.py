import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import work_window


class WorkWindowTests(unittest.TestCase):
    def evaluate(self, count, hour=16, minute=30):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / '.work-state'
            state.mkdir()
            # Existing installations have two persisted gap entries.
            (state / '2026-10-16.json').write_text(json.dumps({
                'schedule_version': 2,
                'first_session': '2026-10-16T09:00:00+05:30',
                'gaps_minutes': [60, 60],
            }))
            timestamps = '\n'.join(f'2026-10-16T{9+i:02}:00:00+05:30' for i in range(count))
            with patch.object(work_window, 'ROOT', root), patch.object(
                work_window.subprocess, 'run', return_value=SimpleNamespace(stdout=timestamps, returncode=0)
            ):
                return work_window.evaluate(datetime(2026, 10, 16, hour, minute, tzinfo=work_window.IST))

    def test_old_schedule_supports_fourth_commit(self):
        self.assertTrue(self.evaluate(3, 12)['due'])

    def test_fifth_commit_is_allowed_after_gap(self):
        self.assertTrue(self.evaluate(4)['due'])

    def test_seven_commits_stop_further_work(self):
        self.assertEqual(self.evaluate(7)['reason'], 'daily_limit')

    def test_gap_and_evening_cutoff_are_preserved(self):
        self.assertFalse(self.evaluate(3, 11, 59)['due'])
        self.assertFalse(self.evaluate(4, 18)['due'])

    def test_unreadable_history_never_allows_a_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(work_window, 'ROOT', Path(directory)), patch.object(
                work_window.subprocess, 'run',
                return_value=SimpleNamespace(stdout='', returncode=1)
            ):
                result = work_window.evaluate(datetime(2026, 10, 16, 10, tzinfo=work_window.IST))
                self.assertFalse(result['due'])
                self.assertEqual(result['reason'], 'git_history_unavailable')

    def test_random_plan_is_persisted_and_fits_the_workday(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(work_window, 'ROOT', root), patch.object(
                work_window.subprocess, 'run',
                return_value=SimpleNamespace(stdout='', returncode=0)
            ):
                now = datetime(2026, 10, 16, 10, tzinfo=work_window.IST)
                work_window.evaluate(now)
                path = root / '.work-state' / '2026-10-16.json'
                plan = path.read_text()
                work_window.evaluate(now)
                self.assertEqual(plan, path.read_text())
                values = json.loads(plan)
                first = datetime.fromisoformat(values['first_session'])
                self.assertEqual(first.hour, 9)
                self.assertLessEqual(first.minute, 40)
                self.assertEqual(len(values['gaps_minutes']), 6)
                self.assertTrue(all(60 <= gap <= 80 for gap in values['gaps_minutes']))


if __name__ == '__main__':
    unittest.main()
