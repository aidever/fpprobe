# syntax=docker/dockerfile:1
FROM rust:1-alpine AS build
RUN apk add --no-cache musl-dev
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src src
COPY web web
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked && cp target/release/fpprobe /fpprobe

FROM scratch
COPY --from=build /fpprobe /fpprobe
VOLUME /var/lib/fpprobe
EXPOSE 8080 8443
ENTRYPOINT ["/fpprobe"]
