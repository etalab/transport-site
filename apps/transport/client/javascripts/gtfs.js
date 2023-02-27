import { Socket } from 'phoenix'
import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer } from '@deck.gl/layers';

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

Leaflet.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom
}).addTo(map);

const deckGLLayer = new LeafletLayer({
    views: [new MapView({ repeat: true })],
    layers: []
})
map.addLayer(deckGLLayer);

// triggered both by "zoomend" and the end of move
map.on('moveend', function(event) {
    var bounds = map.getBounds();
    var a = map.latLngToLayerPoint([bounds.getNorth(), bounds.getWest()]);
    var b = map.latLngToLayerPoint([bounds.getSouth(), bounds.getEast()]);
    var width_pixels = b.x - a.x;
    var height_pixels = b.y - a.y;

    var params = new URLSearchParams({
        "width_pixels": width_pixels,
        "height_pixels": height_pixels,
        "south": bounds.getSouth(),
        "east": bounds.getEast(),
        "west": bounds.getWest(),
        "north": bounds.getNorth()
    });

    var url = `/explore/gtfs-stops-data?${params}`;

    // https://colorbrewer2.org/#type=sequential&scheme=YlOrRd&n=6
    var palette = [[255, 255, 178], [254, 217, 118], [254, 178, 76], [253, 141, 60], [240, 59, 32], [189, 0, 38]];

    var colorFunc = function(d) {
        let count = d[2];
        if (count > 25) {
            return palette[0];
        } else if (count > 15) {
            return palette[1];
        } else if (count > 10) {
            return palette[2];
        } else if (count > 5) {
            return palette[3];
        } else if (count > 2) {
            return palette[4];
        } else {
            return palette[5];
        }
    };

    fetch(url)
        .then(data => data.json())
        .then(json => {

            var data = json;
            console.log(data);
            const scatterplotLayer = new ScatterplotLayer({
                id: 'scatterplot-layer',
                data,
                pickable: true,
                opacity: 1.0,
                stroked: true,
                filled: true,
                radiusScale: 6,
                radiusMinPixels: 1,
                radiusMaxPixels: 100,
                lineWidthMinPixels: 1,
                getPosition: d => [d[1], d[0]],
                getRadius: function(d) {
                    var c = d[2];
                    if (c > 10) {
                        return 6;
                    } else if (c > 5) {
                        return 3;
                    } else {
                        return 2;
                    }
                },
                getFillColor: colorFunc,
                getLineColor: function(d) {
                    let x = colorFunc(d);
                    return [0, 0, 0, 0.5];
                }
            });
            deckGLLayer.setProps({ layers: [scatterplotLayer] });
        })
        .catch(e => console.log(e))
})

map.fitBounds(metropolitanFranceBounds)


export default socket
