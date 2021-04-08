defmodule Transport.Shared.SentryExceptionFilter do
  @moduledoc """
  This module is used to avoid spamming our Sentry server
  and thus consuming our events quota.

  See https://hexdocs.pm/sentry/Sentry.html#module-filtering-exceptions.

  Implementation based on
  https://github.com/getsentry/sentry-elixir/blob/master/lib/sentry/default_event_filter.ex
  """
  @behaviour Sentry.EventFilter

  @ignored_plug_exceptions [
    # default ones
    Phoenix.Router.NoRouteError,
    Plug.Parsers.RequestTooLarge,
    Plug.Parsers.BadEncodingError,
    Plug.Parsers.ParseError,
    Plug.Parsers.UnsupportedMediaTypeError,
    # our additions
    Ecto.NoResultsError,
    Phoenix.NotAcceptableError
  ]

  def exclude_exception?(%x{}, :plug) when x in @ignored_plug_exceptions do
    true
  end

  # "Ignore Plug route not found exception"
  def exclude_exception?(%FunctionClauseError{function: :do_match, arity: 4}, :plug), do: true

  def exclude_exception?(_exception, _source), do: false
end
