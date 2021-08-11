FROM betagouv/transport:elixir-1.12.2-erlang-24.0.3-alpine-3.13.3

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
