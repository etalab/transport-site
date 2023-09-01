defmodule TransportWeb.Live.Feedback do
  # In Phoenix v1.6+ apps, the line below should be: use MyAppWeb, :live_view
  use Phoenix.LiveView
  import TransportWeb.Router.Helpers
  import Phoenix.HTML.Form


  def render(assigns) do
    ~H"""
    <div class="container">
      <h2>Laissez-nous votre avis</h2>
      <%#= form_for @socket, contact_path(@socket, :send_feedback), fn f -> %>
        <form action="/send_feedback" method="post" name="form" target="_blank" novalidate="" class="no-margin">
        <div class="form__group feedback-selector">
          <fieldset>
            <legend class="required">Qu’avez vous pensé de cette page ?</legend>

            <input type="radio" id="like" name="feedback-rating" value="like" />
            <label class="label-inline" for="like"><i class="fa-regular fa-face-smile feedback-emojis"></i></label>
            <input type="radio" id="neutral" name="feedback-rating" value="neutral" />
            <label class="label-inline" for="neutral"><i class="fa-regular fa-face-meh feedback-emojis"></i></label>
            <input type="radio" id="dislike" name="feedback-rating" value="dislike" />
            <label class="label-inline" for="dislike"><i class="fa-regular fa-face-frown feedback-emojis"></i></label>
          </fieldset>
        </div>

        <div id="full-feedback-form" class="hidden">
          <div class="form__group">
            <label for="feedback-text" class="required">Pourquoi ?</label>
            <textarea name="feedback-text"></textarea>
          </div>

          <div class="form__group">
            <label for="feedback-email">Votre email (facultatif)</label>
            <input id="feedback-email" name="feedback-email" required="" type="email" />
          </div>

          <button class="button" type="submit" name="send-feedback-email" id="submit">Envoyer l’avis</button>
        </div>
      </form>

      <%# end %>

      <script>
        document.querySelectorAll(".feedback-selector label").forEach(
          function(el) {
          el.addEventListener('click', function() {
            document.getElementById("full-feedback-form").classList.remove("hidden");
          });
         }
        );
      </script>
    </div>
    """
  end

  def mount(_params, _other_params, socket) do
    {:ok, socket}
  end
end
