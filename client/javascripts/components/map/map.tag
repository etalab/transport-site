<map>
    <script type="es6">
        import { addMap } from './map'
        this.root.innerHTML = '<div id="canvas" class="canvas"></div>'
        addMap('canvas', '/data/home.geojson')
    </script>
</map>
