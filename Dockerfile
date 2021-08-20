# NOTE: for this experiment, I'll build the converter right here (mostly copy pasting
# what is at https://github.com/etalab/gtfs_converter/blob/master/Dockerfile) but ultimately we'll
# make a dedicated Docker image with all the binaries we want to leverage, then simply copying them
# it at deploy time.
FROM rust:1.54-alpine3.13 as builder
WORKDIR /
# git is not inside "rust alpine", apparently
RUN apk add git
RUN git clone --depth=1 --branch main --single-branch https://github.com/rust-transit/gtfs-to-geojson.git
WORKDIR /gtfs-to-geojson
RUN cargo build --release
RUN strip ./target/release/gtfs-geojson
RUN ./target/release/gtfs-geojson --help

FROM betagouv/transport:elixir-1.12.2-erlang-24.0.3-alpine-3.13.3

COPY --from=builder /gtfs-to-geojson/target/release/gtfs-geojson /usr/local/bin/gtfs-geojson

Repro for arch issue (I get "not found")
RUN /usr/local/bin/gtfs-geojson --help

RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ gnu-libiconv-dev

RUN mkdir phoenixapp
WORKDIR /phoenixapp
COPY ./ /phoenixapp

RUN mix do deps.get --only prod

RUN elixir --version
RUN erl -noshell -eval 'erlang:display(erlang:system_info(system_version))' -eval 'init:stop()'
RUN node --version

ENV PORT 8080
ENV MIX_ENV prod
RUN mix deps.compile
RUN mix phx.digest
RUN cd apps/transport/client && yarn install && npm run build

EXPOSE 8080

ENTRYPOINT ["mix", "phx.migrate_phx.server"]
