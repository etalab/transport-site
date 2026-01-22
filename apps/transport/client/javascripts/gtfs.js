import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers'

import { MapView } from '@deck.gl/core'
import { IGN } from './map-config'

// Default location is Paris
const DEFAULT_LAT = 48.8575
const DEFAULT_LNG = 2.3514
const DEFAULT_ZOOM = 6

function getMapParamsFromUrlPath () {
    // Example Path: /gtfs-stops?@34.0522,-118.2437,10
    const path = window.location.search
    const parts = path.split('?@')

    // If there is no '?@' segment, return defaults
    if (parts.length < 2) {
        return { lat: DEFAULT_LAT, lng: DEFAULT_LNG, zoom: DEFAULT_ZOOM }
    }

    const coordsStr = parts[1]
    const [latStr, lngStr, zoomStr] = coordsStr.split(',')

    const lat = parseFloat(latStr) || DEFAULT_LAT
    const lng = parseFloat(lngStr) || DEFAULT_LNG

    const zoom = parseInt(zoomStr, 10) || DEFAULT_ZOOM
    return { lat, lng, zoom }
}

const { lat, lng, zoom } = getMapParamsFromUrlPath()
const map = Leaflet.map('map', { renderer: Leaflet.canvas() }).setView([lat, lng], zoom)

Leaflet.tileLayer(IGN.url, IGN.config).addTo(map)

let currentPopup = null

function showPopup (info) {
    if (currentPopup) {
        currentPopup.remove()
        currentPopup = null
    }
    if (info.picked && info.object) {
        let content = ''
        if (info.object.count !== undefined) {
            content = `${info.object.count.toString()} stops`
        } else if (info.object.properties) {
            content = `${info.object.properties.d_title} - ${info.object.properties.stop_id} <pre><code>${JSON.stringify(info.object, null, 4)}</code></pre>`
        }
        if (content) {
            setTimeout(() => {
                currentPopup = Leaflet.popup()
                    .setLatLng([info.coordinate[1], info.coordinate[0]])
                    .setContent(content)
                    .openOn(map)
            }, 0)
        }
    }
}

const deckGLLayer = new LeafletLayer({
    views: [new MapView({ repeat: true })],
    layers: []
})
map.addLayer(deckGLLayer)

map.on('movestart', function (event) {
    deckGLLayer.setProps({
        layers: deckGLLayer.props.layers.map(l => l.clone({ visible: false }))
    })
})

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
        north: bounds.getNorth(),
        zoom_level: map.getZoom()
    })

    const url = `/api/gtfs-stops?${params}`

    // https://coolors.co/gradient-palette/2655ff-ff9822?number=5 and https://coolors.co/gradient-palette/ff9822-ce1313?number=5
    const palette = [[38, 85, 255], [92, 102, 200], [147, 119, 145], [201, 135, 89], [255, 152, 34], [243, 119, 30], [231, 86, 27], [218, 52, 23], [206, 19, 19]]

    const colorFunc = function (v) {
        return palette[Math.min(Math.floor(v * 9), 8)]
    }

    fetch(url)
        .then(data => data.json())
        .then(jsonResponse => {
            let layer = null
            let tooltip = null
            // clustered response is marked with a special type so that we can recognize it here
            if (jsonResponse.type === 'clustered') {
                const data = jsonResponse.data.map(x => { return { lat: x[0], lon: x[1], count: x[2] } })
                const maxCount = Math.max(...data.map(a => a.count))
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
                    getPosition: d => [d.lon, d.lat],
                    getRadius: d => 2,
                    getFillColor: d => colorFunc(maxCount < 3 ? 0 : d.count / maxCount),
                    getLineColor: d => colorFunc(maxCount < 3 ? 0 : d.count / maxCount),
                    onClick: showPopup
                })
                layer = scatterplotLayer
                tooltip = function (d) {
                    if (d.picked) {
                        return `${d.object.count.toString()} stops`
                    } else {
                        return false
                    }
                }
            } else if (jsonResponse.type === 'FeatureCollection') { // non-clustered response is GeoJSON, also with a "type" marker
                const data = jsonResponse
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
                    getElevation: 30,
                    onClick: showPopup
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

function updateUrl () {
    const center = map.getCenter()
    const zoom = map.getZoom()

    const lat = center.lat.toFixed(5)
    const lng = center.lng.toFixed(5)
    const z = zoom

    const newPath = `?@${lat},${lng},${z}`
    const currentPath = window.location.pathname.split('?@')[0]

    window.history.pushState(
        { lat, lng, z },
        '',
        currentPath + newPath
    )
}

map.on('moveend', updateUrl)

map.fire('moveend', { source: 'load' })

document.querySelector('#autoComplete').addEventListener('selection', function (event) {
    event.preventDefault()
    map.flyTo([event.detail.selection.value.y, event.detail.selection.value.x], 12)
})
