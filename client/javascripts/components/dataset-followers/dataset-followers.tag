<dataset-followers>
  <button if={ this.opts.user_id && !user_subscribed } onclick={ subscribe }>
    { opts.subscribe_to_dataset }
  </button>
  <button if={ this.opts.user_id && user_subscribed } onclick={ unsubscribe }>
    { opts.unsubscribe_to_dataset }
  </button>
  <script type="es6">
    this.on('before-mount', () => {
        this.user_subscribed = false
    })

    this.on('mount', () => {
        if (this.opts.user_id) {
            this.set_is_user_subscribed(
                this.opts.site + '/api/1/datasets/' + this.opts.dataset_id + '/followers/'
            )
        }
    })

    this.set_is_user_subscribed = (page) => {
        fetch(page, {
            method: 'GET',
            mode: 'cors'
        }).then((response) => {
            return response.json()
        }).then((data) => {
            this.user_subscribed = data.data.reduce(
                (acc, value) => { return acc || (value['follower']['id'] === this.opts.user_id) },
                false
            )
            if (!this.user_subscribed && data.next_page != null) {
                this.set_is_user_subscribed(data.next_page)
            }
            if (this.user_subscribed) {
                this.update()
            }
        })
    }

    this.subscribe = (e) => {
        e.preventDefault()
        let headers = new Headers()
        headers.append('X-CSRF-TOKEN', document.querySelector('meta[name=csrf]').content)

        fetch('/api/datasets/' + this.opts.dataset_id + '/followers/', {
            credentials: 'same-origin',
            headers: headers,
            method: 'POST',
            mode: 'cors'
        }).then((data) => {
            this.user_subscribed = true
            this.update()
        })
    }

    this.unsubscribe = (e) => {
        e.preventDefault()
        let headers = new Headers()
        headers.append('X-CSRF-TOKEN', document.querySelector('meta[name=csrf]').content)
        fetch('/api/datasets/' + this.opts.dataset_id + '/followers/', {
            credentials: 'same-origin',
            headers: headers,
            method: 'DELETE',
            mode: 'cors'
        }).then((data) => {
            this.user_subscribed = false
            this.update()
        })
    }
  </script>
</dataset-followers>
