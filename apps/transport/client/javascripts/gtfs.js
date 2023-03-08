import { Socket } from 'phoenix'
import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers'

import { MapView } from '@deck.gl/core'

const socket = new Socket('/socket', { params: { token: window.userToken } })
socket.connect()

const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/istopopoki/ckg98kpoc010h19qusi9kxcct/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoiaXN0b3BvcG9raSIsImEiOiJjaW12eWw2ZHMwMGFxdzVtMWZ5NHcwOHJ4In0.VvZvyvK0UaxbFiAtak7aVw',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20
}

const metropolitanFranceBounds = [[51.1, -4.9], [41.2, 9.8]]
const map = Leaflet.map('map', { renderer: Leaflet.canvas() })

Leaflet.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom
}).addTo(map)

const deckGLLayer = new LeafletLayer({
    views: [new MapView({ repeat: true })],
    layers: []
})
map.addLayer(deckGLLayer)

// triggered both by "zoomend" and the end of move
map.on('moveend', function (event) {
    const bounds = map.getBounds()
    const a = map.latLngToLayerPoint([bounds.getNorth(), bounds.getWest()])
    const b = map.latLngToLayerPoint([bounds.getSouth(), bounds.getEast()])
    const widthPixels = b.x - a.x
    const heightPixels = b.y - a.y

    const params = new URLSearchParams({
        width_pixels: widthPixels,
        height_pixels: heightPixels,
        south: bounds.getSouth(),
        east: bounds.getEast(),
        west: bounds.getWest(),
        north: bounds.getNorth()
    })

    const url = `/explore/gtfs-stops-data?${params}`

    // https://coolors.co/gradient-palette/2655ff-ff9822?number=5 and https://coolors.co/gradient-palette/ff9822-ce1313?number=5
    const palette = [[38, 85, 255], [92, 102, 200], [147, 119, 145], [201, 135, 89], [255, 152, 34], [243, 119, 30], [231, 86, 27], [218, 52, 23], [206, 19, 19]]

    const colorFunc = function (v) {
        return palette[Math.min(Math.floor(v * 10), 9)]
    }

    fetch(url)
        .then(data => data.json())
        .then(jsonResponse => {
            let layer = null
            let tooltip = null
            if (jsonResponse.type === 'clustered') {
                const data = jsonResponse.data
                const maxCount = Math.max(...data.map(a => a[2]))
                const scatterplotLayer = new ScatterplotLayer({
                    id: 'scatterplot-layer',
                    data,
                    pickable: true,
                    opacity: 0.8,
                    stroked: true,
                    filled: true,
                    radiusUnits: 'pixels',
                    radiusScale: 1,
                    lineWidthMinPixels: 1,
                    getPosition: d => [d[1], d[0]],
                    getRadius: d => 2,
                    getFillColor: d => colorFunc(maxCount < 3 ? 0 : d[2] / maxCount),
                    getLineColor: d => colorFunc(maxCount < 3 ? 0 : d[2] / maxCount)
                })
                layer = scatterplotLayer
                tooltip = function (d) {
                    if (d.picked) {
                        return `${d.object.at(2).toString()} stops`
                    } else {
                        return false
                    }
                }
            } else if (jsonResponse.type === 'detailed') {
                const data = jsonResponse.data
                const geoJsonLayer = new GeoJsonLayer({
                    id: 'geojson-layer',
                    data,
                    pickable: true,
                    stroked: false,
                    filled: true,
                    extruded: true,
                    pointType: 'circle',
                    lineWidthScale: 20,
                    lineWidthMinPixels: 2,
                    getFillColor: [38, 85, 255],
                    getLineColor: [38, 85, 255],
                    getPointRadius: 100,
                    pointRadiusMinPixels: 1,
                    pointRadiusMaxPixels: 3,
                    getLineWidth: 1,
                    getElevation: 30
                })
                layer = geoJsonLayer
                tooltip = function (d) {
                    if (d.picked) {
                        return { html: `${d.object.properties.d_title} - ${d.object.properties.stop_id} <pre><code>${JSON.stringify(d.object, null, 4)}</code></pre>` }
                    }
                }
            }
            deckGLLayer.setProps({
                getTooltip: tooltip,
                getCursor: () => 'crosshair',
                layers: [layer]
            })
        })
        .catch(e => console.log(e))
})

map.fitBounds(metropolitanFranceBounds)

export default socket
