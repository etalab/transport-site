defmodule TransportWeb.Live.GTFSDiffSelectLive.Analysis do
  @moduledoc """
  Analysis step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext

  def analysis_step(%{diff_logs: _, error_msg: _} = assigns) do
    ~H"""
    <div class="container">
      <div class="panel">
        <h4><%= dgettext("validations", "Processing") %></h4>
        <div :for={log <- @diff_logs}>
          <%= raw(log) %>...
        </div>
      </div>

      <div :if={@error_msg}>
        <span class="red"><%= @error_msg %></span>
      </div>
    </div>
    """
  end
end
