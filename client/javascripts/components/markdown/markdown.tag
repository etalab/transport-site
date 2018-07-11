<markdown>
    <div></div>

    <script type="es6">
        import { Converter } from 'showdown'

        this.converter = new Converter()

        this.set = () => {
            const text = this.opts.content || this.root._innerHTML
            this.root.firstChild.innerHTML = this.converter.makeHtml(text)
        }

        this.on('update', this.set)
        this.on('mount', this.set)
    </script>
</markdown>
