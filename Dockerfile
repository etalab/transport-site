FROM ghcr.io/etalab/transport-ops:elixir-1.14.0-erlang-24.3.4.5-ubuntu-focal-20211006-transport-tools-1.0.4

RUN mkdir phoenixapp
WORKDIR /phoenixapp
COPY ./ /phoenixapp
RUN mv  /transport-tools /phoenixapp

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
