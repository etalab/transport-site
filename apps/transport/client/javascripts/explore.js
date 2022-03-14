import { Socket } from 'phoenix'

let socket = new Socket("/socket", { params: { token: window.userToken } });
socket.connect();
let channel = socket.channel("explore", {})
channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })

import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet';
import { ScatterplotLayer } from '@deck.gl/layers';
import { MapView } from '@deck.gl/core';

const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/istopopoki/ckg98kpoc010h19qusi9kxcct/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoiaXN0b3BvcG9raSIsImEiOiJjaW12eWw2ZHMwMGFxdzVtMWZ5NHcwOHJ4In0.VvZvyvK0UaxbFiAtak7aVw',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20
}

const metropolitan_france_bounds = [[51.1, -4.9], [41.2, 9.8]]

const map = Leaflet.map("map", { renderer: Leaflet.canvas() }).fitBounds(metropolitan_france_bounds);
L.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom
}).addTo(map)

function prepareLayer(layerId, layerData) {
    return new ScatterplotLayer({
        id: layerId,
        data: layerData,
        pickable: true,
        opacity: 1,
        stroked: true,
        filled: true,
        radiusScale: 3,
        radiusMinPixels: 1,
        radiusMaxPixels: 4,
        lineWidthMinPixels: 1,
        getPosition: d => {
            return [d.position.longitude, d.position.latitude];
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
    layers: []
});
map.addLayer(deckLayer);

channel.on("vehicle-positions", payload => {
    console.log("update...", payload)
    // TODO: track multiple layers, one per topic, and pass the props accordingly,
    // only changing the layer that has changed, and relying on their identification
    deckLayer.setProps({ layers: [prepareLayer("some-gtfs-rt", payload.vehicle_positions)] });
    console.log("Updated...")
})

export default socket