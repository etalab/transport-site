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

Then:

```sh
protoc --elixir_out=. gtfs-realtime.proto
```
