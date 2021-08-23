# Experimental:
# - I'm using Ubuntu instead of Alpine for the Elixir base, so we move to a more widespread architecture
# - This allows to use `rust:latest` to compile and run the GTFS converter
# - Ultimately we'll likely switch to Ubuntu via `transport-ops` base image and standardize on that, due
#   to widespread support
# - The rust bits partially come from https://github.com/etalab/gtfs_converter/blob/master/Dockerfile
# - Later, we'll build a dedicated image with all tools as binaries inside

FROM rust:latest as builder
WORKDIR /
RUN git clone --depth=1 --branch main --single-branch https://github.com/rust-transit/gtfs-to-geojson.git
WORKDIR /gtfs-to-geojson
RUN cargo build --release
RUN strip ./target/release/gtfs-geojson
RUN ./target/release/gtfs-geojson --help

# FROM betagouv/transport:elixir-1.12.2-erlang-24.0.3-alpine-3.13.3
FROM hexpm/elixir:1.12.2-erlang-24.0.5-ubuntu-focal-20210325

COPY --from=builder /gtfs-to-geojson/target/release/gtfs-geojson /usr/local/bin/gtfs-geojson

# Repro for arch issue (I got "not found" on incorrect arch, now it works)
RUN /usr/local/bin/gtfs-geojson --help

# Adapting what is in https://github.com/etalab/transport-ops/blob/master/transport-site/Dockerfile
# but for Ubuntu 20 instead of Alpine

RUN apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential git curl

# NOTE: 14.x because we use a 14.x version at the moment
RUN curl https://deb.nodesource.com/setup_14.x | bash
RUN curl https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get -y update && apt-get -y install nodejs yarn

RUN mix local.hex --force
RUN mix local.rebar --force

# regular start from there
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
