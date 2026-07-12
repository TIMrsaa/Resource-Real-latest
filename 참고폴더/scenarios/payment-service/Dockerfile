# syntax=docker/dockerfile:1.6
FROM golang:1.25-alpine AS builder
WORKDIR /workspace
COPY shared/ shared/
COPY payment-service/ payment-service/
RUN cd payment-service && \
    GOFLAGS=-mod=mod GOWORK=off CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/payment-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/payment-service /payment-service
EXPOSE 9090
USER nonroot:nonroot
ENTRYPOINT ["/payment-service"]
