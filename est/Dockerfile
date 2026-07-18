# syntax=docker/dockerfile:1

FROM golang:1.22-alpine AS build
RUN apk add --no-cache git
WORKDIR /src
COPY go.mod ./
COPY internal/ internal/
COPY cmd/ cmd/
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /est-server ./cmd/est-server

FROM alpine:3.20
RUN apk add --no-cache openssl ca-certificates wget
COPY --from=build /est-server /usr/local/bin/est-server
EXPOSE 8443
ENTRYPOINT ["/usr/local/bin/est-server"]
