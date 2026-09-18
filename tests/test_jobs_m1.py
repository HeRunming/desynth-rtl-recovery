import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from harness.jobs import JobStateError, JobStore, obligation_key


class JobStoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "jobs.sqlite"

    def submit(self, store, **kw):
        args = dict(source_hash="source", candidate_hash="candidate", engine="abc", budget_s=5)
        args.update(kw)
        return store.submit(**args)

    def test_crash_and_reopen_require_explicit_recovery(self):
        code = """import os, sys
from harness.jobs import JobStore
s = JobStore(sys.argv[1])
s.submit('source', 'candidate', engine='abc', budget_s=5)
s.claim()
os._exit(9)
"""
        completed = subprocess.run([sys.executable, "-c", code, str(self.path)])
        self.assertEqual(completed.returncode, 9)
        with JobStore(self.path) as store:
            attempt, = store.list_attempts()
            self.assertEqual(attempt["status"], "running")
            self.assertIsNone(attempt["result"])
            self.assertIsNone(store.claim(attempt["attempt_id"]))
            self.assertEqual(store.recover_interrupted(), [attempt["attempt_id"]])
            recovered = store.get(attempt["attempt_id"])
            self.assertEqual(recovered["status"], "cancelled")
            self.assertTrue(recovered["result"]["interrupted"])
            self.assertEqual(store.recover_interrupted(), [])
        with JobStore(self.path) as store:
            self.assertEqual(store.get(attempt["attempt_id"]), recovered)

    def test_retry_budgets_preserve_timeout_and_metadata(self):
        with JobStore(self.path) as store:
            first = self.submit(store, candidate_metadata={"operation": "full_adder"}, options={"cec": "&cec"})
            store.claim(first["attempt_id"])
            timed_out = store.finish(first["attempt_id"], "timeout", {"status": "timeout", "reason": "deadline"}, log_paths=["abc.log"])
            second = self.submit(store, budget_s=1800, options={"cec": "cec"})
            self.assertNotEqual(first["attempt_id"], second["attempt_id"])
            self.assertEqual(first["obligation_key"], second["obligation_key"])
            self.assertEqual(second["candidate_metadata"], {"operation": "full_adder"})
            store.claim(second["attempt_id"])
            store.finish(second["attempt_id"], "proven", {"status": "proven"})
            self.assertEqual(store.get(first["attempt_id"]), timed_out)
            self.assertEqual([r["budget_s"] for r in store.list_attempts()], [5, 1800])

    def test_results_and_identity_are_immutable(self):
        with JobStore(self.path) as store:
            attempt = self.submit(store, candidate_metadata={"region": [1]})
            aid = attempt["attempt_id"]
            with self.assertRaises(JobStateError):
                store.finish(aid, "proven", {})
            store.claim(aid)
            for result in ({"status": "counterexample"}, {"source_hash": "other"}, {"candidate_hash": "other"}):
                with self.assertRaises(JobStateError):
                    store.finish(aid, "proven", result)
                self.assertEqual(store.get(aid)["status"], "running")
            terminal = store.finish(aid, "counterexample", {"inputs": {"a": 1}})
            with self.assertRaises(JobStateError):
                store.finish(aid, "proven", {})
            with self.assertRaises(JobStateError):
                self.submit(store, candidate_metadata={"region": [2]})
            self.assertEqual(store.get(aid), terminal)
            self.assertEqual(len(store.list_attempts()), 1)

    def test_source_isolation_and_scoped_recovery(self):
        with JobStore(self.path) as store:
            a = self.submit(store)
            b = self.submit(store, source_hash="another_source")
            self.assertNotEqual(a["obligation_key"], b["obligation_key"])
            store.claim(a["attempt_id"])
            store.claim(b["attempt_id"])
            store.recover_interrupted(source_hash="source")
            self.assertEqual(store.get(b["attempt_id"])["status"], "running")
            self.assertEqual(len(store.list_attempts(source_hash="source", candidate_hash="candidate")), 1)
            self.assertEqual(store.list_attempts(status="running")[0]["attempt_id"], b["attempt_id"])
            self.assertNotEqual(obligation_key("a", "bc"), obligation_key("ab", "c"))

    def test_independent_connections_cannot_claim_twice(self):
        with JobStore(self.path) as one, JobStore(self.path) as two:
            first = self.submit(one)
            second = self.submit(one)
            self.assertEqual(two.claim()["attempt_id"], first["attempt_id"])
            self.assertIsNone(one.claim(first["attempt_id"]))
            self.assertEqual(one.claim()["attempt_id"], second["attempt_id"])
            self.assertIsNone(two.claim())

    def test_invalid_submissions_do_not_pollute_database(self):
        with JobStore(self.path) as store:
            for budget in (0, -1, float("nan"), float("inf"), True):
                with self.assertRaises(ValueError):
                    self.submit(store, budget_s=budget)
            with self.assertRaises(ValueError):
                self.submit(store, options={"bad": float("nan")})
            self.assertEqual(store.list_attempts(), [])


if __name__ == "__main__":
    unittest.main()
