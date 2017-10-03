<organizations-search>
    <form role="search">
        <input type="search" value={ keyword }  onkeyup={ update_query } placeholder="recherche">
    </form>

    <section class="organizations">
        <organization each={ organizations.slice(0, 10) } name={ name } description={ description } slug={ slug }/>
    </section>

    <script type="es6">
        this.organizations = []
        this.keyword       = ''
        this.searching     = false

        this.fetch_orgs = () => {
            if (this.searching) { return }

            this.searching  = true
            this.oldKeyword = this.keyword

            fetch(`${process.env.DATAGOUVFR_SITE}/api/1/organizations/?q=${this.oldKeyword}`)
                .then(response => { return response.json() })
                .then(data => {
                    this.update({ organizations: data.data })
                    this.searching = false

                    if (this.oldKeyword !== this.keyword) {
                        this.fetch_orgs()
                    }
                })
        }

        this.update_query = function(event) {
            this.keyword = event.target.value
            this.fetch_orgs()
        }
    </script>
</organizations-search>
