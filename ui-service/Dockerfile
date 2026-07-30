# syntax=docker/dockerfile:1

# ---- build: compile the static bundle ----
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci

COPY . .

# Vite bakes VITE_* vars into the JS bundle at build time (see
# docs/architecture.md §11/§15) -- it cannot be an ordinary runtime env var the
# way the other services' config is, since this becomes static files served to
# any browser on the LAN.
ARG VITE_BACKEND_BASE_URL
ENV VITE_BACKEND_BASE_URL=${VITE_BACKEND_BASE_URL}
RUN npm run build

# ---- runtime: nginx, non-root, serves the built bundle only ----
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 5173

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:5173/ >/dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]
