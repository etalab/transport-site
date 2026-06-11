`gtfs-realtime.pb.ex` is the compiled result of `gtfs-realtime.proto` via the Elixir protobuf compiler plugin.

Do not edit it by hand please!

## How to regenerate the files

* [gtfs-realtime.proto source](https://raw.githubusercontent.com/google/transit/master/gtfs-realtime/proto/gtfs-realtime.proto)
* Check `mix.lock` and use the same `protobuf` version for `protoc-gen-elixir`.

On Mac:

```sh
brew install protobuf
mix escript.install hex protobuf 0.15.0 # change this to match mix.lock
asdf reshim elixir
```

On Fedora (with asdf):

```sh
sudo dnf install -y protobuf-compiler
mix escript.install hex protobuf 0.15.0 # change this to match mix.lock
asdf reshim elixir
```

Then:

```sh
cd apps/transport/lib/transport/protobuf
protoc --elixir_out=. gtfs-realtime.proto
```
