`gtfs-realtime.pb.ex` is the compiled result of `gtfs-realtime.proto` via the elixir protobuf compiler plugin.

Do not edit it by hand please!

### How to regenerate the files

* [gtfs-realtime.proto source](https://developers.google.com/transit/gtfs-realtime/gtfs-realtime-proto)

On Mac:

```
brew install protobuf
mix escript.install hex protobuf
asdf reshim elixir
```

Then:

```
protoc --elixir_out=. gtfs-realtime.proto
```
