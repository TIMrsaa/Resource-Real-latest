# syntax=docker/dockerfile:1.6
FROM golang:1.25-alpine AS builder
WORKDIR /workspace
COPY shared/ shared/
COPY user-service/ user-service/
RUN cd user-service && \
    GOFLAGS=-mod=mod GOWORK=off CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/user-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/user-service /user-service
EXPOSE 50051 9090
USER nonroot:nonroot
ENTRYPOINT ["/user-service"]
