<discussions>
    <div class="discussion" each={ discussion in discussion_page } id="discussion-{ discussion.id}">
        <div class="discussion__title">
            <h1>{ discussion.title }</h1>
        </div>

        <div class="discussion-comment" each={ comment in discussion.discussion }>
            <div class="discussion-comment__header">
                <a href={ comment.posted_by.page }>
                    { comment.posted_by.first_name } { comment.posted_by.last_name }
                </a>
                <span> { opts.posted_on } </span>
                <span>{ new Date(comment.posted_on).toLocaleString() }</span>
            </div>
            <div class="discussion-comment__content">
                { comment.content }
            </div>
        </div>

        <span if={ !isConnected() } class="discussion-commment__connection-needed">
            { opts.connection_needed }
        </span>

        <a if={ isConnected() && !respond_comment_visible[discussion.id] } onclick={ show_respond_comment }>
            { opts.respond_comment }
        </a>

        <form class="discussion-comment__form"
              if={ respond_comment_visible[discussion.id] }
              onsubmit={ send_comment }>
            <div class="form__group">
                <textarea ref="comment-{ discussion.id }"></textarea>
            </div>

            <div class="form__group">
                <button>{ opts.respond_comment }</button>
            </div>
        </form>
    </div>

    <div class="discussion__post">
        <a if={ isConnected() && !post_discussion_visible } onclick={ show_post_discussion }>
            { opts.post_discussion }
        </a>

        <form class="discussion__form"
              if={ post_discussion_visible }
              onsubmit={ post_discussion }>
            <div class="form__group">
                <input type="text" placeholder={ opts.title } ref="discussion_title">
            </div>

            <div class="form__group">
                <textarea ref="discussion_comment"></textarea>
            </div>

            <div class="form__group">
                <button>{ opts.respond_comment }</button>
            </div>
        </form>
    </div>

    <div class="discussions--error" if={ error }>
        { this.opts.errorText }
    </div>

    <script type="es6">
        this.on('before-mount', () => {
            this.error = false
            this.discussion_page = []
            this.respond_comment_visible = {}
            this.post_discussion_visible = false
        })

        this.on('mount', () => {
            this.update_discussions()
        })

        this.show_respond_comment = (e) => {
            Object.keys(this.respond_comment_visible).map((k) => {
                this.respond_comment_visible[k] = false
            })

            let id = e.target.parentNode.id.split('-')[1]
            this.respond_comment_visible[id] = true
        }

        this.show_post_discussion = (e) => {
            this.post_discussion_visible = true
        }

        this.send_comment = (e) => {
            e.preventDefault()
            let id      = e.target.parentNode.id.split('-')[1]
            let payload = {
                'comment': this.refs['comment-' + id].value
            }
            let headers = new Headers()
            headers.append('X-CSRF-TOKEN', document.querySelector('meta[name=csrf]').content)
            headers.append('Content-Type', 'application/json')

            fetch('/api/discussions/' + id, {
                method: 'POST',
                body: JSON.stringify(payload),
                headers: headers,
                credentials: 'same-origin'
            }).then((response) => {
                this.update_discussions()
            }).catch(() => {
                this.display(false)
            })
        }

        this.post_discussion = (e) => {
            e.preventDefault()
            let payload = {
                'id_': this.opts.datasetid,
                'title': this.refs.discussion_title.value,
                'comment': this.refs.discussion_comment.value
            }
            if (this.opts.type !== 'null') {
                payload['extras'] = {'type': this.opts.type}
            }
            let headers = new Headers()
            headers.append('X-CSRF-TOKEN',
                document.querySelector('meta[name=csrf]').content
            )
            headers.append('Content-Type', 'application/json')

            fetch('/api/discussions', {
                method: 'POST',
                body: JSON.stringify(payload),
                headers: headers,
                credentials: 'same-origin'
            }).then((response) => {
                this.update_discussions()
            }).catch(() => {
                this.display(false)
            })
        }

        this.update_discussions = () => {
            this.discussion_page = []
            this.get_discussion(this.opts.site + '/api/1/discussions/?for=' + this.opts.datasetid)
        }

        this.discussion_is_null = discussion => {
            return this.opts.type === 'null' &&
                 (discussion.extras === undefined ||
                 discussion.extras === null ||
                 Object.keys(discussion.extras).length === 0 ||
                 discussion.extras.type === null)
        }

        this.filter_discussion_by_type = discussion => {
            return this.discussion_is_null(discussion) ||
            discussion.extras.type === this.opts.type
        }

        this.get_discussion = (url) => {
            fetch(url, {
                method: 'GET',
                mode: 'cors'
            }).then((response) => {
                return response.json()
            }).then((data) => {
                this.discussion_page = this.discussion_page.concat(
                    data.data.filter(this.filter_discussion_by_type)
                )
                Object.values(this.discussion_page).map((discussion) => {
                    this.respond_comment_visible[discussion.id] = false
                })
                this.post_discussion_visible = false
                if (data.next_page != null) {
                    this.get_discussion(data.next_page)
                }
                this.update()
            })
        }

        this.isConnected = () => {
            return this.opts.connected === 'true'
        }
  </script>
</discussions>
