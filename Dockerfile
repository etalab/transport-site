FROM ghcr.io/etalab/transport-ops:elixir-1.17.3-erlang-27.1-ubuntu-focal-20240530-transport-tools-1.0.7

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
# Package source code for Sentry https://hexdocs.pm/sentry/upgrade-10-x.html
RUN mix sentry.package_source_code

EXPOSE 8080

# See https://github.com/etalab/transport-site/issues/1384
#
# Here I discovered that a default cookie is generated automatically by Erlang,
# and that its value will be the same when running Phoenix vs. running an iex
# on the same node (but it will be different on e.g. site vs worker).
#
# This cookie is stored in `~/.erlang_cookie` and can be read programmatically
# via `:erlang.get_cookie()`.
#
# So as long as a `-sname` has been set at Phoenix startup, this is good enough to
# allow iex connection with the following command (after SSH):
#
# `iex --sname console --remsh node`
#
# I was also able to define a custom cookie, and I'm saving the notes in case we
# decide the default cookie is not good enough, or detect a situation where it could
# be guessable in a way or another.
#
# Add this right above the `ENTRYPOINT`:
#
# `ENV ERL_FLAGS="-cookie $ELIXIR_NODE_SECRET_COOKIE"`
#
# (`-cookie` is not a typo, this is different from `elixir --cookie`)
#
# You will need to make sure to define the variable, otherwise it will fallback
# to the automatically generated cookie value.
#
# Setting `ERL_FLAGS` via `ENV` makes it possible not to introduce a subshell
# to evaluate the variable in `ENTRYPOINT`, something that would introduce other
# problems such as the behaviour of kill on the container (subprocesses).
#
# If you use `ERL_FLAGS` with a custom cookie, the command to connect to the node
# will be slightly different:
# `iex --sname console --cookie $ELIXIR_NODE_SECRET_COOKIE --remsh node`
#

ENTRYPOINT ["elixir", "--sname", "node", "-S", "mix", "phx.migrate_phx.server"]
