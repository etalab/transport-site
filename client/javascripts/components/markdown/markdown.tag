<markdown>
    <div></div>

    <script type="es6">
        import { Converter } from 'showdown'

        this.converter = new Converter()

        this.set = () => {
            this.root.firstChild.innerHTML = this.converter.makeHtml(this.opts.content)
        }

        this.on('update', this.set)
        this.on('mount', this.set)
    </script>
</markdown>
