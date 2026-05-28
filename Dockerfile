FROM golang:1.25-bookworm AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Build the nsw-api binary (assuming main package is in cmd/nsw-api)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/nsw-api ./cmd/server

FROM alpine:3.19 AS runtime
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/nsw-api /usr/local/bin/nsw-api
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nsw-api"]
