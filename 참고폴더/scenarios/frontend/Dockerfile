# syntax=docker/dockerfile:1.6
FROM golang:1.25-alpine AS builder
WORKDIR /workspace
COPY shared/ shared/
COPY frontend/ frontend/
RUN cd frontend && \
    GOFLAGS=-mod=mod GOWORK=off CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/frontend .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/frontend /app/frontend
COPY --from=builder /workspace/frontend/templates/ /app/templates/
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/frontend"]
