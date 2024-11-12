export const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/transport-pan/clj8j9fla009701pie4nrfo62/tiles/{tileSize}/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoidHJhbnNwb3J0LXBhbiIsImEiOiJjbGo4anJodWUxOXY0M3BxeWo3bHlrMXoxIn0.qFfjiswVf2TaLQ2YmB-Mnw',
    attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20,
    tileSize: 512,
    zoomOffset: -1
}

export const IGN = {
    url: 'https://data.geopf.fr/wmts?&REQUEST=GetTile&SERVICE=WMTS&VERSION=1.0.0&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/png&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}',
    config: {
        minZoom: 0,
        maxZoom: 18,
        attribution: 'IGN-F/Géoportail',
        tileSize: 256,
        className: 'ign-tile'
    }
}
