FROM elixir:1.5.1

# Install system dependencies
RUN apt-get update \
    && apt-get install -y apt-transport-https \
                          lsb-release \
                          curl

# Install Node
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
# Install PhantomJS
RUN mkdir /tmp/phantomjs \
    && curl -L https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 | tar -xvj -C /tmp/phantomjs --strip-components=1 phantomjs-2.1.1-linux-x86_64/bin \
    && mv /tmp/phantomjs/bin/phantomjs /usr/bin \
    && rm -rf /tmp/phantomjs
RUN curl https://gist.githubusercontent.com/maukoquiroga/48e9aa501ca8c7d63615644d67c08648/raw/d11c050b68d463da3c221a59ddc0d0f473daa834/phantomjs > /etc/init.d/phantomjs
RUN chmod +x /etc/init.d/phantomjs

# Install Heroku
RUN wget -qO- https://cli-assets.heroku.com/install-ubuntu.sh | sh
