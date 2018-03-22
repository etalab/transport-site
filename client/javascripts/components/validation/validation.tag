<validation>
    <div class="validation__title">
        <h1>Validation</h1>
    </div>
    <catalogue-errors catalogue_id={ this.opts.catalogue_id }>
    </catalogue-errors>

    <script type="es6">
        this.on('before-mount', () => {
            this.validation = []
            this.to_display = 'warnings'
            this.page = 0
            this.page_count = 0
            this.page_size = 10
            this.messages = []
            this.empty_messages = {
                'errors': this.opts.no_errors,
                'warnings': this.opts.no_warnings,
                'notices': this.opts.no_notices}
            this.validator = 'catalogue'
        })

        this.on('mount', () => {
            this.validator = 'catalogue'
            this.update()
        })

        this.get_validations = (slug) => {
            this.validator = 'catalogue'
            fetch('/api/datasets/' + slug + '/validations/'
            ).then((response) => {
                return response.json()
            }).then((data) => {
                this.validation = data
                this.init_warnings()
                this.update()
            })
        }

        this.init_errors = () => {
            this.init_messages('errors')
        }

        this.init_warnings = () => {
            this.init_messages('warnings')
        }

        this.init_notices = () => {
            this.init_messages('notices')
        }

        this.init_messages = (_type) => {
            this.to_display = _type
            this.page = 0
            this.show_messages()
        }

        this.show_messages = () => {
            this.messages = this.validation[this.to_display]
            this.page_count = Math.floor(this.messages.length / this.page_size)
            this.messages = this.messages.slice(this.page * this.page_size,
                (this.page + 1) * this.page_size)
            this.update()
        }

        this.next = () => {
            this.page = this.page + 1
            this.show_messages()
        }

        this.before = () => {
            this.page = this.page - 1
            this.show_messages()
}
    </script>

</validation>
