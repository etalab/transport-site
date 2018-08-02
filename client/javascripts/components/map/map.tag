<map>
    <div class="map"></div>

    <script type="es6">
        import { addMap } from './map'

        this.render = () => addMap(this.root.firstChild, '/api/stats/', '/api/stats/regions', this.opts)
        this.on('mount', this.render)
    </script>
</map>
