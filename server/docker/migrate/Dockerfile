FROM docker.io/supabase/postgres:17.6.1.127@sha256:be60aee15997daca475b710b734bc6bfe52cd544dcd7e9fd2ff58210b6747d83

COPY scripts/migrate.sh /opt/pomodoist/migrate.sh
COPY supabase/migrations /opt/pomodoist/migrations
COPY supabase/legacy /opt/pomodoist/legacy
COPY database/application-fingerprint.sql /opt/pomodoist/application-fingerprint.sql
COPY database/enable-selfhost.sql /opt/pomodoist/enable-selfhost.sql

ENTRYPOINT ["/bin/sh", "/opt/pomodoist/migrate.sh"]
