defmodule TransportWeb.Live.GTFSDiffSelectLive.Analysis do
  @moduledoc """
  Analysis step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext

  def analysis_step(%{diff_logs: _, error_msg: _} = assigns) do
    ~H"""
    <div id="gtfs-diff-analysis" class="container">
      <div class="panel">
        <h4><%= dgettext("validations", "Processing") %></h4>
        <div :for={log <- @diff_logs}>
          <%= raw(log) %>…
        </div>
      </div>

      <div :if={@error_msg}>
        <span class="red"><%= @error_msg %></span>
      </div>

      <.action_bar :if={@error_msg} />
    </div>
    """
  end

  defp action_bar(%{} = assigns) do
    ~H"""
    <div class="actions">
      <button class="button-outline primary" type="button" phx-click="start-over">
        <i class="fa fa-rotate-left"></i>&nbsp;<%= dgettext("validations", "Start over") %>
      </button>
    </div>
    """
  end
end
