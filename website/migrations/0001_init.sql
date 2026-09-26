CREATE TABLE users
(
    id                TEXT PRIMARY KEY,
    username          TEXT    NOT NULL,
    global_name       TEXT,
    avatar            TEXT,
    credits           INTEGER NOT NULL CHECK (credits >= 0),
    credits_reset_day TEXT    NOT NULL,
    last_ip           TEXT,
    created_at        INTEGER NOT NULL,
    last_login_at     INTEGER NOT NULL
);

CREATE TABLE sessions
(
    id         TEXT PRIMARY KEY,
    user_id    TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    ip         TEXT
);

CREATE INDEX sessions_user_id ON sessions (user_id);
CREATE INDEX sessions_expires_at ON sessions (expires_at);

CREATE TABLE jobs
(
    id         TEXT PRIMARY KEY,
    user_id    TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status     TEXT    NOT NULL CHECK (status IN ('queued', 'running', 'done', 'failed', 'cancelled')),
    config     TEXT    NOT NULL,
    wanted     INTEGER NOT NULL,
    cost       INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    result     TEXT,
    error      TEXT,
    runpod_id  TEXT
);

CREATE INDEX jobs_user_id_created_at ON jobs (user_id, created_at DESC);
CREATE INDEX jobs_status ON jobs (status);
CREATE UNIQUE INDEX jobs_runpod_id ON jobs (runpod_id) WHERE runpod_id IS NOT NULL;
