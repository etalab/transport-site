# FROM ghcr.io/etalab/transport-tools:master as transport-tools

FROM betagouv/transport:test-transport-tools

RUN mkdir phoenixapp
WORKDIR /phoenixapp
COPY ./ /phoenixapp
RUN mv  /transport-tools /phoenixapp

# COPY --from=transport-tools /usr/local/bin/gtfs-geojson ./transport-tools
# RUN chmod +x ./transport-tools/gtfs-geojson

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
