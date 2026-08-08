# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY src/go-version-app.go .

ARG TARGETOS
ARG TARGETARCH

# Build a static Linux binary
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o go-version-app go-version-app.go

# Runtime stage (no Go installed)
FROM scratch

WORKDIR /app
COPY --from=builder /app/go-version-app /app/go-version-app

EXPOSE 3000
ENV VERSION=docker-test

USER 65532:65532

ENTRYPOINT ["/app/go-version-app"]
