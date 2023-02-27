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
const map = Leaflet.map('map', { renderer: Leaflet.canvas() });

// triggered both by "zoomend" and the end of move
map.on('moveend', function(event) {
    var bounds = map.getBounds();
    bounds = {
        south: bounds.getSouth(),
        north: bounds.getNorth(),
        west: bounds.getWest(),
        east: bounds.getEast()
    }

    var a = map.latLngToLayerPoint([bounds.north, bounds.west]);
    var b = map.latLngToLayerPoint([bounds.south, bounds.east]);

    var width_pixels = b.x - a.x;
    var height_pixels = b.y - a.y;
    var width_degrees = bounds.east - bounds.west;
    var height_degrees = bounds.south - bounds.north;

    var snap_x = Math.abs(width_degrees / (width_pixels / 5.0));
    var snap_y = Math.abs(height_degrees / (height_pixels / 5.0));
    console.log(snap_x, snap_y)
})

map.fitBounds(metropolitanFranceBounds)

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

export default socket
