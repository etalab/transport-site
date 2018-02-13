defmodule Transport.DataValidation.Commands.ValidateFeedSourceTest do
  use ExUnit.Case, async: true
  alias Transport.DataValidation.Aggregates.{Project, FeedSource}
  alias Transport.DataValidation.Commands.ValidateFeedSource

  doctest ValidateFeedSource
end
