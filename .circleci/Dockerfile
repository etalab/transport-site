FROM elixir:1.5.1

# Install system dependencies
RUN apt-get update \
    && apt-get install -y apt-transport-https \
                          lsb-release \
                          curl

# Install node
RUN curl -sL https://deb.nodesource.com/setup_7.x | bash -
RUN apt-get update -qy \
    && apt-get install -y nodejs

# Install app dependencies
RUN mix local.hex --force
RUN mix local.rebar --force
RUN npm i -g yarn \
             eslint \
             eslint-config-standard \
             eslint-plugin-import \
             eslint-plugin-node \
             eslint-plugin-promise \
             eslint-plugin-standard \
             sass-lint
