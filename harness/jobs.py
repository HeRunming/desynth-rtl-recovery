"""Persistent execution records, not a scheduler or proof acceptance authority.

An obligation is bound to both the immutable source and candidate. Every retry
creates a new attempt: engine, options and budget belong to that attempt. A
caller must explicitly recover abandoned running attempts after checking that
their workers are no longer alive. Reopening a database never changes status.
"""
from __future__ import annotations

import hashlib
import json
import math
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any


TERMINAL_STATUSES = frozenset({"proven", "counterexample", "timeout", "unknown",
                               "model_error", "tool_error", "cancelled"})
STATUSES = TERMINAL_STATUSES | {"queued", "running"}


class JobStateError(ValueError):
    """An attempt transition would discard or contradict an existing record."""


def _json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def obligation_key(source_hash: str, candidate_hash: str) -> str:
    if not isinstance(source_hash, str) or not source_hash:
        raise ValueError("source_hash must be a nonempty string")
    if not isinstance(candidate_hash, str) or not candidate_hash:
        raise ValueError("candidate_hash must be a nonempty string")
    return hashlib.sha256(_json([source_hash, candidate_hash]).encode()).hexdigest()


class JobStore:
    """SQLite-backed append-only attempts with atomic claim/finish transitions.

    ``finish`` records a trusted caller's report; a ``proven`` record alone is
    never permission to replace RTL. Existing proof validation remains required.
    Use one instance per thread/process; concurrent instances share the database.
    """

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(self.path), timeout=30, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA foreign_keys = ON")
        self._db.execute("PRAGMA synchronous = FULL")
        try:
            self._db.execute("BEGIN IMMEDIATE")
            version = self._db.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1):
                raise ValueError(f"unsupported job database version: {version}")
            self._db.execute("""CREATE TABLE IF NOT EXISTS obligations (
                obligation_key TEXT PRIMARY KEY, source_hash TEXT NOT NULL,
                candidate_hash TEXT NOT NULL, candidate_metadata TEXT NOT NULL,
                created_at REAL NOT NULL, UNIQUE(source_hash, candidate_hash))""")
            self._db.execute("""CREATE TABLE IF NOT EXISTS attempts (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                attempt_id TEXT NOT NULL UNIQUE,
                obligation_key TEXT NOT NULL REFERENCES obligations(obligation_key),
                engine TEXT NOT NULL, options TEXT NOT NULL, budget_s REAL NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('queued','running','proven',
                    'counterexample','timeout','unknown','model_error','tool_error','cancelled')),
                created_at REAL NOT NULL, started_at REAL, finished_at REAL,
                result TEXT, log_paths TEXT NOT NULL)""")
            self._db.execute("CREATE INDEX IF NOT EXISTS attempts_obligation ON attempts(obligation_key)")
            self._db.execute("""CREATE TRIGGER IF NOT EXISTS terminal_attempt_immutable
                BEFORE UPDATE ON attempts WHEN OLD.status NOT IN ('queued','running')
                BEGIN SELECT RAISE(ABORT, 'terminal attempts are immutable'); END""")
            self._db.execute("PRAGMA user_version = 1")
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            self._db.close()
            raise

    def close(self) -> None:
        self._db.close()

    def __enter__(self) -> "JobStore":
        return self

    def __exit__(self, *_args) -> None:
        self.close()

    def submit(self, source_hash: str, candidate_hash: str, *, engine: str,
               budget_s: float, options: dict | None = None,
               candidate_metadata: dict | None = None) -> dict:
        """Append a queued attempt; omission reuses existing candidate metadata."""
        key = obligation_key(source_hash, candidate_hash)
        if not isinstance(engine, str) or not engine:
            raise ValueError("engine must be a nonempty string")
        if isinstance(budget_s, bool) or not isinstance(budget_s, (int, float)) or not math.isfinite(budget_s) or budget_s <= 0:
            raise ValueError("budget_s must be finite and positive")
        if options is not None and not isinstance(options, dict):
            raise ValueError("options must be an object")
        if candidate_metadata is not None and not isinstance(candidate_metadata, dict):
            raise ValueError("candidate_metadata must be an object")
        metadata = _json(candidate_metadata if candidate_metadata is not None else {})
        option_json = _json(options if options is not None else {})
        attempt_id, now = uuid.uuid4().hex, time.time()
        try:
            self._db.execute("BEGIN IMMEDIATE")
            row = self._db.execute("SELECT candidate_metadata FROM obligations WHERE obligation_key = ?", (key,)).fetchone()
            if row is None:
                self._db.execute("INSERT INTO obligations VALUES (?,?,?,?,?)", (key, source_hash, candidate_hash, metadata, now))
            elif candidate_metadata is not None and row["candidate_metadata"] != metadata:
                raise JobStateError("candidate metadata differs for the same obligation")
            self._db.execute("""INSERT INTO attempts
                (attempt_id,obligation_key,engine,options,budget_s,status,created_at,log_paths)
                VALUES (?,?,?,?,?,'queued',?,'[]')""", (attempt_id, key, engine, option_json, budget_s, now))
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise
        return self.get(attempt_id)

    @staticmethod
    def _decode(row: sqlite3.Row) -> dict:
        record = dict(row)
        for field in ("options", "candidate_metadata", "result", "log_paths"):
            record[field] = json.loads(record[field]) if record[field] is not None else None
        return record

    def get(self, attempt_id: str) -> dict:
        row = self._db.execute("""SELECT a.*, o.source_hash, o.candidate_hash, o.candidate_metadata
            FROM attempts a JOIN obligations o USING(obligation_key) WHERE attempt_id = ?""", (attempt_id,)).fetchone()
        if row is None:
            raise KeyError(attempt_id)
        return self._decode(row)

    def list_attempts(self, *, source_hash: str | None = None,
                      candidate_hash: str | None = None, status: str | None = None) -> list[dict]:
        clauses, values = [], []
        if status is not None and status not in STATUSES:
            raise ValueError("invalid status")
        for name, value in (("source_hash", source_hash), ("candidate_hash", candidate_hash), ("status", status)):
            if value is not None:
                clauses.append(f"{name} = ?")
                values.append(value)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        rows = self._db.execute("""SELECT a.*, o.source_hash, o.candidate_hash, o.candidate_metadata
            FROM attempts a JOIN obligations o USING(obligation_key)""" + where + " ORDER BY sequence", values)
        return [self._decode(row) for row in rows]

    def claim(self, attempt_id: str | None = None) -> dict | None:
        """Atomically claim a queued attempt, or oldest queued when ID omitted."""
        try:
            self._db.execute("BEGIN IMMEDIATE")
            if attempt_id is None:
                row = self._db.execute("SELECT attempt_id FROM attempts WHERE status = 'queued' ORDER BY sequence LIMIT 1").fetchone()
            else:
                row = self._db.execute("SELECT attempt_id FROM attempts WHERE attempt_id = ? AND status = 'queued'", (attempt_id,)).fetchone()
            if row is None:
                self._db.execute("COMMIT")
                return None
            claimed_id = row["attempt_id"]
            self._db.execute("UPDATE attempts SET status = 'running', started_at = ? WHERE attempt_id = ?", (time.time(), claimed_id))
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise
        return self.get(claimed_id)

    def finish(self, attempt_id: str, status: str, result: dict, *,
               log_paths: list[str] | None = None) -> dict:
        """Finish only a running attempt; reject result identity contradictions."""
        if status not in TERMINAL_STATUSES:
            raise ValueError("finish requires a terminal status")
        if not isinstance(result, dict):
            raise ValueError("result must be an object")
        paths = [] if log_paths is None else log_paths
        if not isinstance(paths, list) or any(not isinstance(p, str) for p in paths):
            raise ValueError("log_paths must be a list of strings")
        result_json, paths_json = _json(result), _json(paths)
        try:
            self._db.execute("BEGIN IMMEDIATE")
            record = self.get(attempt_id)
            if record["status"] != "running":
                raise JobStateError("only a running attempt can finish; terminal results cannot be overwritten")
            expected = {"status": status, "source_hash": record["source_hash"], "candidate_hash": record["candidate_hash"]}
            for key, value in expected.items():
                if key in result and result[key] != value:
                    raise JobStateError(f"result {key} contradicts attempt")
            self._db.execute("""UPDATE attempts SET status = ?, result = ?, log_paths = ?, finished_at = ?
                WHERE attempt_id = ?""", (status, result_json, paths_json, time.time(), attempt_id))
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise
        return self.get(attempt_id)

    def recover_interrupted(self, *, reason: str = "worker interrupted", source_hash: str | None = None) -> list[str]:
        """Explicitly cancel abandoned running attempts. Never infer proof success.

        This is an operator action: the caller must ensure selected workers are
        stopped. No lease, liveness detection, or background execution is implied.
        """
        try:
            self._db.execute("BEGIN IMMEDIATE")
            records = self.list_attempts(source_hash=source_hash, status="running")
            for record in records:
                result = {"status": "cancelled", "reason": reason, "interrupted": True,
                          "source_hash": record["source_hash"], "candidate_hash": record["candidate_hash"]}
                self._db.execute("UPDATE attempts SET status = 'cancelled', result = ?, finished_at = ? WHERE attempt_id = ?",
                                 (_json(result), time.time(), record["attempt_id"]))
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise
        return [record["attempt_id"] for record in records]
