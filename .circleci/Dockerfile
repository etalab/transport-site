FROM elixir:1.5.1

# Install system dependencies
RUN apt-get update \
    && apt-get install -y apt-transport-https \
                          lsb-release \
                          curl

# Install RabbitMQ
RUN apt-get install -y rabbitmq-server

# Install Node
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash -
RUN apt-get update -qy \
    && apt-get install -y nodejs

# Install app dependencies
RUN mix local.hex --force
RUN mix local.rebar --force
RUN npm i -g yarn

# Install PhantomJS
RUN mkdir /tmp/phantomjs \
    && curl -L https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 | tar -xvj -C /tmp/phantomjs --strip-components=1 phantomjs-2.1.1-linux-x86_64/bin \
    && mv /tmp/phantomjs/bin/phantomjs /usr/bin \
    && rm -rf /tmp/phantomjs
RUN curl https://gist.githubusercontent.com/maukoquiroga/48e9aa501ca8c7d63615644d67c08648/raw/d11c050b68d463da3c221a59ddc0d0f473daa834/phantomjs > /etc/init.d/phantomjs
RUN chmod +x /etc/init.d/phantomjs

#Install data-validator
RUN apt-get install -y mongodb-server python-pip python-virtualenv
RUN git clone https://github.com/etalab/transport-validator
WORKDIR transport-validator
RUN virtualenv venv
RUN chmod +x /transport-validator/venv/bin/activate
RUN venv/bin/pip install -r requirements.txt
RUN curl https://gist.githubusercontent.com/l-vincent-l/4169fd3e7a7112f724e09a5c2d852ed7/raw/a71c002746727de8cf1490396aec64bd2c5f94e8/celeryd > /etc/default/celeryd
RUN curl https://raw.githubusercontent.com/celery/celery/3.1/extra/generic-init.d/celeryd > /etc/init.d/celeryd
RUN chmod +x /etc/init.d/celeryd
RUN useradd -N -M --system -s /bin/bash celery && groupadd celery && usermod -aG celery celery
RUN mkdir /var/run/celery && chown -R celery:celery /var/run/celery
RUN mkdir /var/log/celery && chown -R celery:celery /var/log/celery
WORKDIR ..

# Install Heroku
RUN wget -qO- https://cli-assets.heroku.com/install-ubuntu.sh | sh
