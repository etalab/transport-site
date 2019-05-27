FROM betagouv/transport:0.4.3

RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ gnu-libiconv-dev
RUN apk add git

RUN mkdir phoenixapp
WORKDIR /phoenixapp
COPY ./ /phoenixapp

RUN mix do deps.get --only prod

ENV PORT 8080
ENV MIX_ENV prod
RUN mix deps.compile
RUN mix phx.digest
RUN cd apps/transport/client && yarn install && npm run deploy

EXPOSE 8080

ENTRYPOINT ["mix", "phx.migrate_phx.server"]
