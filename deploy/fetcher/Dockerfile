ARG GO_IMAGE=golang:1.24.13-bookworm
ARG RUNTIME_IMAGE=alpine:3.19

FROM ${GO_IMAGE} AS builder

WORKDIR /src

COPY services/fetcher/go.mod services/fetcher/go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY services/fetcher ./

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/oil-price-fetcher \
    ./cmd/fetcher

FROM ${RUNTIME_IMAGE}

RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata \
    && addgroup -g 10001 -S app \
    && adduser -u 10001 -S -G app -h /app -s /sbin/nologin app

COPY --from=builder \
     --chown=app:app \
     /out/oil-price-fetcher \
     /usr/local/bin/oil-price-fetcher

USER app

EXPOSE 8002

ENTRYPOINT ["/usr/local/bin/oil-price-fetcher"]