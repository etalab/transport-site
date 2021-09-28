FROM ghcr.io/etalab/transport-tools:master

FROM betagouv/transport:elixir-1.12.2-erlang-24.0.4-ubuntu-focal-20210325

RUN mkdir phoenixapp
RUN mkdir /phoenixapp/external-tools
WORKDIR /phoenixapp
COPY ./ /phoenixapp

COPY --from=0 /usr/local/bin/gtfs-geojson ./external-tools
RUN chmod +x ./external-tools/gtfs-geojson

RUN mix do deps.get --only prod

RUN elixir --version
RUN erl -noshell -eval 'erlang:display(erlang:system_info(system_version))' -eval 'init:stop()'
RUN node --version

ENV PORT 8080
ENV MIX_ENV prod
RUN mix deps.compile
RUN cd apps/transport/client && yarn install && npm run build
# assets digest must happen after the npm build step
RUN mix phx.digest

EXPOSE 8080

ENTRYPOINT ["mix", "phx.migrate_phx.server"]
