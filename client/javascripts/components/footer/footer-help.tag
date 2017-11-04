<footer-help>
  <div class="footer-help__message footer__message--success" if={ successVisible }>
    { opts.mail_sent }
  </div>
  <div class="footer-help__message footer__message--error" if={ errorVisible }>
    { opts.mail_error }
  </div>
  <div>
    <a href="#"onclick={toggleVisibility}><div class="footer-help__round" if={ roundVisible }>?</div></a>
    <div class="footer-help__contact" if={ contactVisible }>
      <a class="footer-help__contact--close" onclick={toggleVisibility}>{ opts.close }</a>
      <div class="footer-help__contact--header">
        <h6>Contact</h6>
      </div>
      <form onsubmit={ sendMail }>
        <div class="form__group">
          <input type="email" value="" ref="email" id="email" placeholder="{ opts.email_address }">
        </div>
        <div class="form__group">
          <textarea placeholder="{ opts.ask_for_help }" ref="demande" id="demande"></textarea>
        </div>
        <button>{ opts.send_email }</button>
      </form>
    </div>
  </div>
  <script>
  this.on('mount', () => {
    this.roundVisible = true
    this.contactVisible = false
    this.successVisible = false
    this.errorVisible = false
    this.update()
  })

  this.toggleVisibility = function() {
      this.roundVisible = !this.roundVisible
      this.contactVisible = !this.contactVisible
      this.update()
  }

  this.sendMail = (e) => {
    this.roundVisible = false
    e.preventDefault()
    let form = new FormData()
    form.append("email", this.refs.email.value)
    form.append("demande", this.refs.demande.value)

    let headers = new Headers()
    headers.append("X-CSRF-TOKEN", document.querySelector("meta[name=csrf]").content)
    fetch("/send_mail", {
      method: "POST",
      body: form,
      headers: headers,
      credentials: 'same-origin'
    }).then( response => {
      this.display(response.ok)
      this.update()
    }).catch( error => {
      this.display(false)
    })
  }

  this.display = (success) => {
    this.contactVisible = false
    if (success) {
      this.successVisible = true
    } else {
      this.errorVisible = true
    }
    this.update()
    setTimeout(this.hideResultDiv, 3000)
  }

  this.hideResultDiv = () => {
      this.roundVisible = true
      this.errorVisible = false
      this.successVisible = false
      this.update()
  }

  </script>
</footer-help>
