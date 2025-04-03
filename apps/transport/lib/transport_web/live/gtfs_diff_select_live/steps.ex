defmodule TransportWeb.Live.GTFSDiffSelectLive.Steps do
  @moduledoc """
  Results step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext
  use Phoenix.Component

  def steps(%{current_step: _} = assigns) do
    ~H"""
    <div id="gtfs-diff-steps" class="container">
      <ul class="steps-form">
        <li class={step_completion(@current_step, :setup)}>
          <div><%= dgettext("validations", "Setup") %></div>
        </li>
        <li class={step_completion(@current_step, :analysis)}>
          <div><%= dgettext("validations", "Analysis") %></div>
        </li>
        <li class={step_completion(@current_step, :results)}>
          <div><%= dgettext("validations", "Results") %></div>
        </li>
      </ul>
    </div>
    """
  end

  defp step_completion(current_step, expected_step) do
    cond do
      step_progression(current_step) > step_progression(expected_step) -> "done"
      step_progression(current_step) == step_progression(expected_step) -> "active"
      true -> ""
    end
  end

  defp step_progression(step) do
    case step do
      :setup -> 1
      :analysis -> 2
      :results -> 3
    end
  end
end
