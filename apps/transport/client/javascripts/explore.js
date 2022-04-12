import { Socket } from 'phoenix'
import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers'

import { MapView } from '@deck.gl/core'

const socket = new Socket('/socket', { params: { token: window.userToken } })
socket.connect()
const channel = socket.channel('explore', {})
channel.join()
    .receive('ok', resp => { console.log('Joined successfully', resp) })
    .receive('error', resp => { console.log('Unable to join', resp) })

const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/istopopoki/ckg98kpoc010h19qusi9kxcct/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoiaXN0b3BvcG9raSIsImEiOiJjaW12eWw2ZHMwMGFxdzVtMWZ5NHcwOHJ4In0.VvZvyvK0UaxbFiAtak7aVw',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20
}

const metropolitanFranceBounds = [[51.1, -4.9], [41.2, 9.8]]
const map = Leaflet.map('map', { renderer: Leaflet.canvas() }).fitBounds(metropolitanFranceBounds)

Leaflet.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom
}).addTo(map)

function prepareLayer (layerId, layerData) {
    return new ScatterplotLayer({
        id: layerId,
        data: layerData,
        pickable: true,
        opacity: 1,
        stroked: true,
        filled: true,
        radiusScale: 3,
        radiusMinPixels: 1,
        radiusMaxPixels: 3,
        lineWidthMinPixels: 1,
        getPosition: d => {
            return [d.position.longitude, d.position.latitude]
        },
        getRadius: d => 100000,
        getFillColor: d => [127, 150, 255],
        getLineColor: d => [100, 100, 200]
    })
}

const deckLayer = new LeafletLayer({
    views: [
        new MapView({
            repeat: true
        })
    ],
    layers: [],
    getTooltip: ({ object }) => object && { html: `transport_resource: ${object.transport.resource_id}<br>id: ${object.vehicle.id}` }
})
map.addLayer(deckLayer)

// internal dictionary
const layers = {}

channel.on('vehicle-positions', payload => {
    if (payload.error) {
        console.log(`Resource ${payload.resource_id} failed to load`)
    } else {
        layers[payload.resource_id] = prepareLayer(payload.resource_id, payload.vehicle_positions)
        deckLayer.setProps({ layers: Object.values(layers) })
    }
})

const bnlcLayer = new LeafletLayer({
    views: [
        new MapView({
            repeat: true
        })
    ],
    layers: [],
    getTooltip: ({ object }) => object && { html: object.properties.nom_lieu }
})
map.addLayer(bnlcLayer)
let bnlcGeoJSON

const checkbox = document.getElementById('bnlc-check')
checkbox.addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        if (bnlcGeoJSON) {
            const geojsonLayer = createBNLCLayer(bnlcGeoJSON)
            bnlcLayer.setProps({ layers: [geojsonLayer] })
        } else {
            fetch('/api/geo-query?data=bnlc')
                .then(data => data.json())
                .then(geojson => {
                    bnlcGeoJSON = geojson
                    const geojsonLayer = createBNLCLayer(bnlcGeoJSON)
                    bnlcLayer.setProps({ layers: [geojsonLayer] })
                }
                )
        }
    } else {
        bnlcLayer.setProps({ layers: [] })
    }

    function createBNLCLayer (geojson) {
        return new GeoJsonLayer({
            id: 'bnlc-layer',
            data: geojson,
            pickable: true,
            stroked: false,
            filled: true,
            extruded: true,
            pointType: 'circle',
            getFillColor: [160, 160, 180, 200],
            getPointRadius: 100,
            pointRadiusUnits: 'meters',
            pointRadiusMinPixels: 2,
            pointRadiusMaxPixels: 10
        })
    }
})

export default socket
