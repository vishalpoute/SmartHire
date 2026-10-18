import unittest
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import patch
import work_window


class WorkWindowTests(unittest.TestCase):
    def evaluate(self, hour, timestamps='', returncode=0):
        with patch.object(work_window.subprocess, 'run', return_value=SimpleNamespace(
            stdout=timestamps, returncode=returncode
        )):
            return work_window.evaluate(datetime(2026, 10, 18, hour, tzinfo=work_window.IST))

    def test_workday_boundaries(self):
        self.assertFalse(self.evaluate(8)['due'])
        self.assertTrue(self.evaluate(9)['due'])
        self.assertTrue(self.evaluate(17)['due'])
        self.assertFalse(self.evaluate(18)['due'])

    def test_no_daily_quota_or_gap(self):
        timestamps = '\n'.join(['2026-10-18T16:59:59+05:30'] * 20)
        result = self.evaluate(17, timestamps)
        self.assertTrue(result['due'])
        self.assertEqual(result['commits_today'], 20)

    def test_history_failures_still_fail_closed(self):
        self.assertFalse(self.evaluate(12, returncode=1)['due'])
        self.assertFalse(self.evaluate(12, 'invalid')['due'])

    def test_counts_only_current_ist_day(self):
        result = self.evaluate(12, '2026-10-17T20:00:00+00:00\n2026-10-17T10:00:00+00:00')
        self.assertEqual(result['commits_today'], 1)


if __name__ == '__main__':
    unittest.main()
