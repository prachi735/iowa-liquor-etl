-- Run log. A run is one CLI command; a step is one unit of work inside it.
CREATE TABLE IF NOT EXISTS ops.run (
    run_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    command     text        NOT NULL,
    started_at  timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    status      text        NOT NULL DEFAULT 'running'
                CHECK (status IN ('running', 'succeeded', 'failed')),
    message     text
);

-- File manifest: one batch per file, keyed by content hash so a file is never loaded twice.
CREATE TABLE IF NOT EXISTS ops.batch (
    batch_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id         bigint      REFERENCES ops.run,
    source_name    text        NOT NULL,
    file_name      text        NOT NULL,
    file_sha256    text        NOT NULL UNIQUE,
    file_bytes     bigint,
    rows_loaded    bigint,
    window_start   date,        -- first and last order date in the file
    window_end     date,
    status         text        NOT NULL DEFAULT 'loaded'
                   CHECK (status IN ('loaded', 'transformed', 'failed')),
    loaded_at      timestamptz NOT NULL DEFAULT now(),
    transformed_at timestamptz
);

CREATE TABLE IF NOT EXISTS ops.run_step (
    step_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id        bigint      NOT NULL REFERENCES ops.run,
    batch_id      bigint      REFERENCES ops.batch,
    step          text        NOT NULL,
    started_at    timestamptz NOT NULL DEFAULT now(),
    finished_at   timestamptz,
    rows_affected bigint,
    status        text        NOT NULL DEFAULT 'running',
    message       text
);

CREATE TABLE IF NOT EXISTS ops.check_result (
    check_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id      bigint      NOT NULL REFERENCES ops.run,
    batch_id    bigint      REFERENCES ops.batch,
    check_name  text        NOT NULL,
    severity    text        NOT NULL CHECK (severity IN ('error', 'warning', 'info')),
    failed_rows bigint      NOT NULL,
    detail      text,
    checked_at  timestamptz NOT NULL DEFAULT now()
);
