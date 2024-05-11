FROM lukemathwalker/cargo-chef:latest-rust-1.78.0 as chef
WORKDIR /app
RUN apt update && apt install lld clang -y

FROM chef AS planner
COPY . .
# Compute a lock-like file for our project.
RUN cargo chef prepare --recipe-path=recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build our project dependencies, not our application!
RUN cargo chef cook --release --recipe-path=recipe.json
# Up to this point, if our dependency tree stays the same,
# all layers should already be cached.
COPY . .
ENV SQLX_OFFLINE true
# Build our application.
RUN cargo build --release --bin zero2prod

FROM debian:bookworm-slim AS runtime
WORKDIR /app
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/zero2prod zero2prod
COPY configuration configuration
ENV APP_ENVIRONMENT production
ENTRYPOINT ["./zero2prod"]

# At this point, the `zero2prod` image only weighs 98MB:
# $ docker images
# REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
# zero2prod    latest    340fda2a2746   11 minutes ago   98MB
# rust         1.78.0    b6d8eec96e0e   9 days ago       1.42GB
# postgres     latest    8e4fc9e18489   2 months ago     431MB
