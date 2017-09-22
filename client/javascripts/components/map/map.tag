import { addMap } from './map'

<map>
    <div class="map"></div>

    <script type="es6">
        this.render = () => addMap(this.root.firstChild, '/data/home.geojson', this.opts)
        this.on('mount', this.render)
    </script>
</map>
