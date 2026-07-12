# syntax=docker/dockerfile:1.6
FROM golang:1.25-alpine AS builder
WORKDIR /workspace
COPY shared/ shared/
COPY notification-service/ notification-service/
RUN cd notification-service && \
    GOFLAGS=-mod=mod GOWORK=off CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/notification-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/notification-service /notification-service
EXPOSE 9090
USER nonroot:nonroot
ENTRYPOINT ["/notification-service"]
