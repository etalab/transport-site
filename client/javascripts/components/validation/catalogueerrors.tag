<catalogue-errors>
    <div if={ this.parent.validator == "catalogue" }>
        <div class="form__group">
            <select onchange={ change_category }>
                <option each={ cat in this.categories } value={ cat.value }>
                      { cat.message } ( { cat.count } )
                </option>
            </select>
        </div>
        <table>
            <thead>
                <tr>
                    <th>Line #</th>
                    <th>{ this.errors[0].entity_type } ID</th>
                    <th> Bad value </th>
                </tr>
            </thead>
        <tbody>
            <tr each={ error in this.errors }>
                 <td>{ error.line_number }</td>
                 <td>{ error.entity_id }</td>
                 <td>{ error.bad_value }</td>
            </tr>
        </tbody>
        </table>
        <div class="validation__pagination">
            <button class="badge-notice" disabled={ page == 0 } onclick={ previous }> < </button>
            <button class="badge-notice" disabled={ page == this.page_count } onclick={ next }> > </button>
        </div>
    </div>
    <script type="es6">
        import { GraphQLClient } from 'graphql-request'
        this.on('before-mount', () => {
            this.page = 0
            this.page_size = 10
            this.page_count = 1
            this.selected_category = null
            this.categories = []
            this.selected_category = null
            this.catalogue_client = new GraphQLClient(
                'http://catalogue.transport.data.gouv.fr/api/manager/graphql',
                {
                    credential: 'credentials',
                    mode: 'cors'
                }
            )
        })

        this.on('mount', () => {
            if (this.opts.catalogue_id != null && this.catalogue_id !== '') {
                this.get_catalogue_validations(this.opts.catalogue_id)
            }
        })

        this.get_catalogue_validations = (catalogueId) => {
            this.validator = 'catalogue'
            var query = `
                query countsQuery($namespace: String) {
                    feed(namespace: $namespace) {
                        row_counts {
                            errors
                        }
                        error_counts {
                            type count message
                        }
                    }
            }`
            var variables = {namespace: catalogueId}

            this.catalogue_client.request(
                query,
                variables
            ).then(data => {
                this.categories = data.feed.error_counts
                    .filter(e => e.type.toLowerCase() in this.parent.opts)
                    .map(e => ({
                        message: this.parent.opts[e.type.toLowerCase()],
                        value: e.type,
                        count: e.count
                    }))
                document.getElementById('stats-warnings').innerHTML = data.feed.row_counts.errors.toString()
                this.select_category(this.categories[0])
                this.update()
            })
        }

        this.select_category = (category) => {
            this.selected_category = category
            this.page = 0
            this.page_count = Math.floor(category.count / this.page_size)
            this.show_page_catalogue()
        }

        this.show_page_catalogue = () => {
            var query = `
            query errorsQuery($namespace: String,
                              $errorType: [String],
                              $limit: Int,
                              $offset: Int) {
                feed(namespace: $namespace) {
                    feed_id
                    feed_version
                    filename
                    errors (error_type: $errorType,
                            limit: $limit,
                            offset: $offset) {
                        error_type
                        entity_type
                        entity_id
                        line_number
                        bad_value
                        entity_sequence 
                    } 
                } 
            }
            `
            var variables = {
                namespace: this.opts.catalogue_id,
                errorType: [this.selected_category.value.toUpperCase()],
                limit: this.page_size,
                offset: this.page_size * this.page
            }
            this.catalogue_client.request(
                query,
                variables
            ).then(data => {
                this.errors  = data.feed.errors
                this.update()
            })
        }

        this.next = () => {
            this.page = this.page + 1
            this.show_page_catalogue()
        }

        this.previous = () => {
            this.page = this.page - 1
            this.show_page_catalogue()
        }

        this.change_category = (e) => {
            this.select_category(this.categories.find(c => e.target.value === c.value))
        }
    </script>
</catalogue-errors>
