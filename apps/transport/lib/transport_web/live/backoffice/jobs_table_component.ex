defmodule JobsTableComponent do
  @moduledoc """
  A live view table for Oban jobs monitoring
  """
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <table class="table">
      <thead>
        <tr>
          <th>id</th>
          <th>state</th>
          <th>queue</th>
          <th>worker</th>
          <th>args</th>
          <th>inserted_at (Paris time)</th>
          <%= if @state == "discarded" do %>
            <th>errors</th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <%= for job <- @jobs do %>
          <tr>
            <td><%= job.id %></td>
            <td><%= job.state %></td>
            <td><%= job.queue %></td>
            <td><%= job.worker %></td>
            <td><%= inspect(job.args) %></td>
            <td><%= format_datetime(job.inserted_at) %></td>
            <%= if @state == "discarded" do %>
              <td><%= inspect(job.errors) %></td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp format_datetime(dt) do
    Shared.DateTimeDisplay.format_datetime_to_paris(dt, "en", no_timezone: true)
  end
end
