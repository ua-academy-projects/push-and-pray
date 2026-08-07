-- Run these commands once as the PostgreSQL administrator.
-- If the role or database already exists, do not run the matching line again.

CREATE USER wildlife_user WITH PASSWORD 'wildlife_password';
CREATE DATABASE wildlife OWNER wildlife_user;
