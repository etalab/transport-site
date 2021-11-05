defmodule JobsTableComponent do
  # If you generated an app with mix phx.new --live,
  # the line below would be: use MyAppWeb, :live_component
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
            </tr>
          <% end %>
        </tbody>
      </table>
    """
  end
end
