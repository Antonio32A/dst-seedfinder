UPDATE users
SET credit_units = MIN(100000, credit_units + (SELECT COALESCE(SUM(max_cost), 0)
                                               FROM jobs
                                               WHERE jobs.user_id = users.id AND jobs.cost IS NULL));

CREATE TABLE jobs_new
(
    id          TEXT PRIMARY KEY,
    user_id     TEXT    NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status      TEXT    NOT NULL CHECK (status IN ('queued', 'starting', 'running', 'done', 'failed', 'cancelled')),
    config      TEXT    NOT NULL,
    wanted      INTEGER NOT NULL,
    max_cost    INTEGER NOT NULL CHECK (max_cost >= 0),
    cost        INTEGER CHECK (cost BETWEEN 0 AND max_cost),
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    result      TEXT,
    error       TEXT,
    instance_id TEXT,
    machine     TEXT,
    started_at  INTEGER,
    finished_at INTEGER
);

INSERT INTO jobs_new (id, user_id, status, config, wanted, max_cost, cost, created_at, updated_at, result, error,
                      finished_at)
SELECT id,
       user_id,
       CASE WHEN cost IS NULL OR status IN ('queued', 'running') THEN 'failed' ELSE status END,
       config,
       wanted,
       max_cost,
       COALESCE(cost, 0),
       created_at,
       updated_at,
       result,
       CASE
           WHEN cost IS NULL OR status IN ('queued', 'running')
               THEN 'The search was stopped by a site update. Your credits were refunded.'
           ELSE error END,
       updated_at
FROM jobs;

DROP TABLE jobs;
ALTER TABLE jobs_new
    RENAME TO jobs;

CREATE INDEX jobs_user_id_created_at ON jobs (user_id, created_at DESC);
CREATE INDEX jobs_status ON jobs (status);
CREATE UNIQUE INDEX jobs_one_active_per_user ON jobs (user_id) WHERE status IN ('queued', 'starting', 'running');
