"""SQLite-backed conversation history.

The schema is forward-only and tracked via ``PRAGMA user_version``.
A structured ``events`` table stores ``tool_call`` /
``tool_observation`` / ``pending_tool_call`` records that the UI
renders alongside chat messages.
"""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import paths as _paths  # noqa: E402

DB_PATH = _paths.history_db_path()

SCHEMA_VERSION = 1

_SCHEMA = """
CREATE TABLE IF NOT EXISTS conversations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at  REAL NOT NULL,
    title       TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_at      REAL NOT NULL,
    role            TEXT NOT NULL,
    content         TEXT NOT NULL,
    meta            TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS messages_by_conv
    ON messages(conversation_id, id);

CREATE TABLE IF NOT EXISTS events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_at      REAL NOT NULL,
    kind            TEXT NOT NULL,
    payload         TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS events_by_conv
    ON events(conversation_id, id);
"""


class History:
    def __init__(self, path: Path = DB_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._path = path
        self._lock = threading.Lock()

        # FIX (durability): integrity-check on open. If the file is
        # malformed we move it aside and start fresh — the only data
        # loss is conversation history, which is non-critical.
        self._integrity_check_or_move_aside()

        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.execute("PRAGMA foreign_keys = ON")
        # WAL improves crash recovery and reduces "database is locked"
        # under concurrent writes from the bridge processes. NORMAL
        # synchronous is the recommended pairing — durable across
        # process crashes, may lose a transaction on power loss.
        try:
            self._conn.execute("PRAGMA journal_mode = WAL")
            self._conn.execute("PRAGMA synchronous = NORMAL")
        except sqlite3.DatabaseError:
            # An OS that does not support WAL (rare) falls back to the
            # default rollback journal. We do not consider this fatal.
            pass
        self._migrate()
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    def _integrity_check_or_move_aside(self) -> None:
        if not self._path.exists() or self._path.stat().st_size == 0:
            return
        try:
            probe = sqlite3.connect(str(self._path))
            try:
                result = probe.execute("PRAGMA integrity_check").fetchone()
            finally:
                probe.close()
        except sqlite3.DatabaseError:
            result = None
        if result and isinstance(result[0], str) and result[0].lower() == "ok":
            return
        # Move the bad file aside; the caller will recreate it.
        ts = time.strftime("%Y%m%dT%H%M%S", time.localtime())
        bad = self._path.with_name(f"{self._path.name}.bad.{ts}")
        try:
            shutil.move(str(self._path), str(bad))
        except OSError:
            # Best effort; if we cannot move it, sqlite3.connect will
            # raise a clearer error below.
            pass

    # ------------------------------------------------------------------
    # Migration
    # ------------------------------------------------------------------
    def _migrate(self) -> None:
        cur = self._conn.execute("PRAGMA user_version")
        current = int(cur.fetchone()[0])
        if current >= SCHEMA_VERSION:
            return
        # Snapshot existing DB once, before any structural change. We
        # only snapshot if the file already contains user data — a
        # brand-new install has nothing worth backing up.
        try:
            has_data = self._conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='conversations'"
            ).fetchone() is not None
        except sqlite3.DatabaseError:
            has_data = False
        if has_data and self._path.exists() and self._path.stat().st_size > 0:
            ts = time.strftime("%Y%m%dT%H%M%S", time.localtime())
            backup = self._path.with_name(f"{self._path.name}.bak.{ts}")
            try:
                shutil.copy2(self._path, backup)
            except OSError:
                # Best-effort: if the snapshot fails the migration
                # still proceeds — additive only, no destructive ops.
                pass
        self._conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        self._conn.commit()

    def _execute(self, sql: str, params: tuple[Any, ...] = ()) -> sqlite3.Cursor:
        with self._lock:
            cur = self._conn.execute(sql, params)
            self._conn.commit()
            return cur

    def create_conversation(self, title: str = "") -> int:
        cur = self._execute(
            "INSERT INTO conversations(created_at, title) VALUES (?, ?)",
            (time.time(), title),
        )
        return int(cur.lastrowid or 0)

    def list_conversations(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._lock:
            cur = self._conn.execute(
                "SELECT id, created_at, title FROM conversations "
                "ORDER BY id DESC LIMIT ?",
                (limit,),
            )
            return [
                {"id": row[0], "created_at": row[1], "title": row[2]}
                for row in cur.fetchall()
            ]

    def conversation_exists(self, conversation_id: int) -> bool:
        with self._lock:
            row = self._conn.execute(
                "SELECT 1 FROM conversations WHERE id = ?",
                (conversation_id,),
            ).fetchone()
        return row is not None

    def add_message(self, conversation_id: int, role: str, content: str,
                    meta: dict[str, Any] | None = None) -> int:
        # FIX-3-17: insert + (conditional) title update must run in a
        # single transaction. Otherwise another reader can land between
        # the two commits and see a conversation with messages but
        # ``title = ''`` — which the UI then caches forever as
        # "(untitled)".
        meta_json = json.dumps(meta or {}, ensure_ascii=False)
        with self._lock:
            cur = self._conn.execute(
                "INSERT INTO messages(conversation_id, created_at, role, "
                "content, meta) VALUES (?, ?, ?, ?, ?)",
                (conversation_id, time.time(), role, content, meta_json),
            )
            message_id = int(cur.lastrowid or 0)
            if role == "user":
                row = self._conn.execute(
                    "SELECT title FROM conversations WHERE id = ?",
                    (conversation_id,),
                ).fetchone()
                if row and not row[0]:
                    self._conn.execute(
                        "UPDATE conversations SET title = ? WHERE id = ?",
                        (content[:60], conversation_id),
                    )
            self._conn.commit()
        return message_id

    def get_messages(self, conversation_id: int) -> list[dict[str, Any]]:
        with self._lock:
            cur = self._conn.execute(
                "SELECT id, created_at, role, content, meta FROM messages "
                "WHERE conversation_id = ? ORDER BY id ASC",
                (conversation_id,),
            )
            rows = cur.fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            try:
                meta = json.loads(row[4])
            except json.JSONDecodeError:
                meta = {}
            out.append({
                "id": row[0],
                "created_at": row[1],
                "role": row[2],
                "content": row[3],
                "meta": meta,
            })
        return out

    # ------------------------------------------------------------------
    # Events (Phase 2: tool_call / tool_observation / pending_tool_call)
    # ------------------------------------------------------------------
    def add_event(self, conversation_id: int, kind: str,
                  payload: dict[str, Any] | None = None) -> int:
        payload_json = json.dumps(payload or {}, ensure_ascii=False)
        cur = self._execute(
            "INSERT INTO events(conversation_id, created_at, kind, payload) "
            "VALUES (?, ?, ?, ?)",
            (conversation_id, time.time(), kind, payload_json),
        )
        return int(cur.lastrowid or 0)

    def get_events(self, conversation_id: int) -> list[dict[str, Any]]:
        with self._lock:
            cur = self._conn.execute(
                "SELECT id, created_at, kind, payload FROM events "
                "WHERE conversation_id = ? ORDER BY id ASC",
                (conversation_id,),
            )
            rows = cur.fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            try:
                payload = json.loads(row[3])
            except json.JSONDecodeError:
                payload = {}
            out.append({
                "id": row[0],
                "created_at": row[1],
                "kind": row[2],
                "payload": payload,
            })
        return out

    def update_event(self, event_id: int, payload: dict[str, Any]) -> None:
        self._execute(
            "UPDATE events SET payload = ? WHERE id = ?",
            (json.dumps(payload, ensure_ascii=False), event_id),
        )

    def close(self) -> None:
        with self._lock:
            self._conn.close()
