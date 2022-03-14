import { Socket } from 'phoenix'

let socket = new Socket("/socket", { params: { token: window.userToken } });
socket.connect();
let channel = socket.channel("explore", {})
channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })

channel.on("vehicle-positions", payload => {
    console.log(payload);
})

import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet';
import { GeoJsonLayer } from '@deck.gl/layers';
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


// TODO: cleanup


// source: Natural Earth http://www.naturalearthdata.com/ via geojson.xyz
const AIR_PORTS = 'https://d2ad6b4ur7yvpq.cloudfront.net/naturalearth-3.3.0/ne_10m_airports.geojson';

const deckLayer = new LeafletLayer({
    views: [
        new MapView({
            repeat: true
        })
    ],
    layers: [
        new GeoJsonLayer({
            id: 'airports',
            data: AIR_PORTS,
            // Styles
            filled: true,
            pointRadiusMinPixels: 2,
            pointRadiusScale: 2000,
            getPointRadius: f => 11 - f.properties.scalerank,
            getFillColor: [200, 0, 80, 180]
        })
    ]
});
map.addLayer(deckLayer);

const featureGroup = L.featureGroup();
featureGroup.addLayer(L.marker([51.4709959, -0.4531566]));
map.addLayer(featureGroup);

export default socket