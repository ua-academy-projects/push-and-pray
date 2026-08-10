FROM golang:1.26-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN GOMAXPROCS=2 CGO_ENABLED=0 go build -p=1 -trimpath -ldflags="-s -w" -o /out/history-service ./cmd/server
RUN GOMAXPROCS=2 CGO_ENABLED=0 go build -p=1 -trimpath -ldflags="-s -w" -o /out/healthcheck ./cmd/healthcheck

FROM cgr.dev/chainguard/static:latest@sha256:24dd7ff8788fdfadda39eeeaefefb6d1cec6002a545935a5f7e017484053734f

COPY --from=build /out/history-service /usr/local/bin/history-service
COPY --from=build /out/healthcheck /usr/local/bin/healthcheck

USER 65532
EXPOSE 8081
ENTRYPOINT ["/usr/local/bin/history-service"]
