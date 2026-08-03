FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN GOMAXPROCS=2 CGO_ENABLED=0 go build -p=1 -trimpath -ldflags="-s -w" -o /out/history-service ./cmd/server

FROM alpine:3.21
RUN adduser -D -u 10001 rateboard && apk add --no-cache ca-certificates
COPY --from=build /out/history-service /usr/local/bin/history-service
USER rateboard
EXPOSE 8081
ENTRYPOINT ["/usr/local/bin/history-service"]
