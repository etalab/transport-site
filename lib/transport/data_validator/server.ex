defmodule Transport.DataValidator.Server do
  @moduledoc """
  DataValidator.Server allows to send to and receive messages from a
  data validation service.
  """

  use GenServer
  alias AMQP.{Connection, Channel, Queue, Exchange, Basic}

  @routing_key "celery"
  @exchange "celery"

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

  @spec init(:ok) :: {:ok, map()} | {:error, any()}
  def init(:ok) do
    with {:ok, conn} <- Connection.open(server_url()),
         {:ok, chan} <- Channel.open(conn),
         :ok <- Exchange.direct(chan, @exchange, durable: true),
         {:ok, _} <- Basic.consume(chan, @exchange) do
      {:ok, %{conn: conn, chan: chan, subscribers: []}}
    else
      {_, error} -> {:error, error}
    end
  end

  def handle_call({:subscribe, pid}, _, state) do
    {:reply, :ok, put_subscriber(state, pid)}
  end

  def handle_cast({:publish, message}, state) do
    :ok = Basic.publish(state.chan, @exchange, @routing_key, message)
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

  defp server_url do
    :amqp
    |> Application.get_all_env
    |> Keyword.get(:rabbitmq_url)
  end

  defp put_subscriber(state, pid) do
    Map.put(state, :subscribers, [pid | state.subscribers])
  end

  defp broadcast(subscribers, message) do
    Enum.each(subscribers, &send(&1, message))
  end
end
