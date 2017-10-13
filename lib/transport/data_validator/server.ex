defmodule Transport.DataValidator.Server do
  @moduledoc """
  DataValidator.Server allows to send to and receive messages from a
  data validation service.
  """

  use GenServer
  alias AMQP.{Connection, Channel, Queue, Exchange, Basic}

  @exchange "data_validations"
  @queue "data_validations"

  ## Client API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: :publisher)
  end

  def subscribe do
    GenServer.call(:publisher, {:subscribe, self()})
  end

  def validate_data(url) do
    GenServer.cast(:publisher, {:publish, url})
  end

  ## Server Callbacks

  def init(:ok) do
    {:ok, conn} = Connection.open
    {:ok, chan} = Channel.open(conn)
    {:ok, _}    = Queue.declare(chan, @queue)
    :ok         = Exchange.fanout(chan, @exchange)
    :ok         = Queue.bind(chan, @queue, @exchange)
    {:ok, _}    = Basic.consume(chan, @exchange)
    {:ok, %{conn: conn, chan: chan, subscribers: []}}
  end

  def handle_call({:subscribe, pid}, _, state) do
    {:reply, :ok, put_subscriber(state, pid)}
  end

  def handle_cast({:publish, message}, state) do
    :ok = Basic.publish(state.chan, @exchange, @queue, message)
    {:noreply, state}
  end

  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag}}, state) do
    :ok = Basic.ack(state.chan, tag)
    broadcast(state.subscribers, {:ok, %{publish: payload}})
    {:noreply, state}
  end

  def terminate(_, state) do
    Connection.close(state.conn)
  end

  # private

  defp put_subscriber(state, pid) do
    Map.put(state, :subscribers, [pid | state.subscribers])
  end

  defp broadcast(subscribers, message) do
    Enum.each(subscribers, &send(&1, message))
  end
end
