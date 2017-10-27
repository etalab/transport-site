defmodule Transport.DataValidator.Server do
  @moduledoc """
  DataValidator.Server allows to send to and receive messages from a
  data validation service.
  """

  use GenServer
  use AMQP
  alias UUID

  @exchange "celery"
  @routing_key "celery"
  @publish_options [content_type: "application/json",
                    content_encoding: "utf-8",
                    persistent: true]

  ## Client API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: :publisher)
  end

  def validate_data(url) do
    GenServer.call(:publisher, {:apply_async, "tasks.perform", [args: [url]]})
  end

  ## Server Callbacks

  @spec init(:ok) :: {:ok, map()} | {:error, any()}
  def init(:ok) do
    with {:ok, conn} <- Connection.open(server_url()),
         {:ok, chan} <- Channel.open(conn) do
      {:ok, %{conn: conn, chan: chan, exchange: @exchange}}
    else
      {_, error} -> {:error, error}
    end
  end

  def handle_call({:apply_async, task, options}, _, state) do
    with %{chan: channel} <- state,
         id <- make_id(),
         {:ok, message} <- make_message(task, id, options),
         :ok <- Basic.publish(channel, @exchange, @routing_key, message,
                              @publish_options) do
      {:reply, {:ok, id}, state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
      {error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, _, _}, state) do
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

  defp make_id do
    UUID.uuid4()
  end

  defp make_message(task, id, options) do
    %{
        id: id,
        task: task,
        args: Keyword.get(options, :args, []),
        kwargs: Keyword.get(options, :kwargs, %{})
    }
    |> Poison.encode
  end
end
