FROM betagouv/transport:0.1.1

RUN mkdir phoenixapp
WORKDIR phoenixapp

COPY ./mix.exs /phoenixapp/mix.exs
COPY ./mix.lock /phoenixapp/mix.lock

RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix do deps.get

COPY ./ /phoenixapp

ENV PORT 8080
ENV MIX_ENV prod
RUN mix deps.compile
RUN mix phx.digest
RUN cd client && yarn install && npm run deploy

EXPOSE 8080

ENTRYPOINT ["mix", "phx.migrate_phx.server"]
