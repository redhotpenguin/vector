FROM registry.hub.docker.com/lukemathwalker/cargo-chef:0.1.31-rust-1.55 as chef
WORKDIR vector

#
# PLANNER
#
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

#
# BUILDER
#
FROM chef AS builder
ARG VECTOR_FEATURES
COPY --from=planner /vector/recipe.json recipe.json
RUN apt-get -y update && apt-get -y install build-essential cmake libclang-dev libsasl2-dev
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
RUN cargo build --release --bin vector --no-default-features --features "${VECTOR_FEATURES}"

#
# TARGET
#
FROM gcr.io/distroless/cc-debian11
COPY --from=builder /vector/target/release/vector /usr/bin/vector
VOLUME /var/lib/vector/

# Smoke test
RUN ["vector", "--version"]

ENTRYPOINT ["/usr/bin/vector"]
