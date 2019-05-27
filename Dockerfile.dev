FROM betagouv/transport:0.4.3

RUN apk add inotify-tools
RUN apk add postgresql-client>=11

RUN mkdir /app/
RUN mkdir /app/_build
RUN mkdir /app/deps/
WORKDIR /app/

ADD mix.exs mix.lock /app/
ADD config /app/config/
ADD apps /app/apps/
