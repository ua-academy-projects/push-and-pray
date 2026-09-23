# database_migrations

Runs the immutable database image as a one-shot container against the private
RDS or Cloud SQL endpoint. The image records applied migration filenames and
checksums in `schema_migrations`; an already applied file is skipped, while a
modified applied file causes deployment to fail.

The role expects registry authentication to be configured and receives the
database password from `resolve_secrets`.
