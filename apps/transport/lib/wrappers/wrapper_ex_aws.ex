defmodule Transport.Wrapper.ExAWS do
  @moduledoc """
  Central access point for the ExAWS behaviour defined at
  https://github.com/ex-aws/ex_aws/blob/master/lib/ex_aws/behaviour.ex
  in order to provide easy mocking during tests.
  """

  def impl, do: Application.get_env(:transport, :ex_aws_impl)
end
