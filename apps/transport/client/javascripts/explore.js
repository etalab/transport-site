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


const data = [
    {
        "position": {
            "bearing": null,
            "latitude": 48.62916946411133,
            "longitude": 6.294188976287842,
            "odometer": null,
            "speed": null
        },
        "trip": {
            "trip_id": "672480005:12"
        },
        "vehicle": {
            "id": "zenbus:Vehicle:661810001:LOC"
        }
    },
    {
        "position": {
            "bearing": null,
            "latitude": 48.60530090332031,
            "longitude": 6.357180118560791,
            "odometer": null,
            "speed": null
        },
        "trip": {
            "trip_id": "690160036:13"
        },
        "vehicle": {
            "id": "zenbus:Vehicle:644560001:LOC"
        }
    }
]

const dataLayer = new ScatterplotLayer({
    id: 'scatterplot-layer',
    data,
    pickable: true,
    opacity: 1,
    stroked: true,
    filled: true,
    radiusScale: 3,
    radiusMinPixels: 1,
    radiusMaxPixels: 2,
    lineWidthMinPixels: 1,
    getPosition: d => {
        console.log(d);
        let a = [d.position.longitude, d.position.latitude];
        return a;
    },
    getRadius: d => 100000,
    getFillColor: d => [127, 150, 255],
    getLineColor: d => [100, 100, 200]
})

const deckLayer = new LeafletLayer({
    views: [
        new MapView({
            repeat: true
        })
    ],
    layers: [dataLayer]
});
map.addLayer(deckLayer);

export default socket