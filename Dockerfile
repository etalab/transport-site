FROM betagouv/transport:0.3.0

RUN apk add git

RUN mkdir phoenixapp
WORKDIR /phoenixapp
COPY ./ /phoenixapp

RUN mix do deps.get --only prod

ENV PORT 8080
ENV MIX_ENV prod
RUN mix deps.compile
RUN mix phx.digest
RUN cd client && yarn install && npm run deploy

EXPOSE 8080

ENTRYPOINT ["mix", "phx.migrate_phx.server"]
