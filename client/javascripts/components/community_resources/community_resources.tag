<communityresources>
    <h1>{ this.opts.title }</h1>
    <ul if={ this.data && this.data.data }>
        <li each={ resource, i in this.data.data }>
            <div class="documentation">
                <div class="side-pan community-resources__side-pan">
                    <div if={ resource.hasOwnProperty("organization") }>
                        <div class="community-resources__logo">
                            <img src={ resource.organization.logo_thumbnail }>
                        </div>
                        <div class="community-resources__organization-name">
                            <h3>{ resource.organization.name }</h3>
                        </div>
                    </div>
                </div>
                <div class="main-pan">
                    <h2>{ resource.title }</h2>
                    <p>{ resource.description }</p>
                    <i class="icon icon--download" aria-hidden="true"></i>
                    <a href={ resource.url}>{ this.opts.download }</a>
                </div>
            </div>
        <li>
    </ul>

    <script type="es6">
        this.on('before-mount', () => {
            this.data = null
        })

        this.on('mount', () => {
            fetch(this.opts.site + '/api/1/datasets/' +  this.opts.slug + '/'
            ).then((response) => {
                return response.json()
            }).then((data) => {
                fetch(this.opts.site + '/api/1/datasets/community_resources/?dataset=' + data.id
                ).then((response) => {
                    return response.json()
                }).then((data) => {
                    this.data = data
                    this.update()
                })
            })
        })
    </script>
</communityresources>
