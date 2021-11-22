defmodule JobsTableComponent do
  @moduledoc """
  A live view table for Oban jobs monitoring
  """
  use Phoenix.LiveComponent

  def render(assigns) do
    ~L"""
      <table class="table">
        <thead>
          <tr>
            <th>id</th>
            <th>state</th>
            <th>queue</th>
            <th>args</th>
            <th>inserted_at</th>
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
              <td><%= inspect(job.args) %></td>
              <td><%= job.inserted_at %></td>
              <%= if @state == "discarded" do %>
                <td><%= inspect(job.errors) %></td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    """
  end
end
