`gtfs-realtime.pb.ex` is the compiled result of `gtfs-realtime.proto` via the Elixir protobuf compiler plugin.

Do not edit it by hand please!

## How to regenerate the files

* [gtfs-realtime.proto source](https://raw.githubusercontent.com/google/transit/master/gtfs-realtime/proto/gtfs-realtime.proto)

On Mac:

```sh
brew install protobuf
mix escript.install hex protobuf
asdf reshim elixir
```

On Fedora (with asdf):

```sh
sudo dnf install -y protobuf-compiler
mix escript.install hex protobuf
asdf reshim elixir
```

Then:

```sh
cd apps/transport/lib/transport/protobuf
protoc --elixir_out=. gtfs-realtime.proto
# If protoc generated transit_realtime/gtfs-realtime.pb.ex, keep a single canonical file:
mv transit_realtime/gtfs-realtime.pb.ex ./gtfs-realtime.pb.ex
rmdir transit_realtime
```
