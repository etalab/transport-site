import L from 'leaflet'

/**
 * Represents a Mapbox object.
 * @type {Object}
 */
const Mapbox = {
    url: 'https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoibC12aW5jZW50LWwiLCJhIjoiY2pzMWtlNG90MXA5cTQ5dGYwNDRyMDRvayJ9.RhYAa9O0Qla5zhJAb9iwJA',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 18,
    id: 'mapbox.light'
}

function initilizeMap (id) {
    const map = L.map(id, { renderer: L.canvas() }).setView([46.505, 2], 5)
    L.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        id: Mapbox.id
    }).addTo(map)

    const fg = L.featureGroup().addTo(map)
    return { map, fg }
}

function createDatasetMap (divId, datasetDatagouvId) {
    const { map, fg } = initilizeMap(divId)
    fetch(`/api/datasets/${datasetDatagouvId}/geojson`)
        .then(data => data.json())
        .then(geojson => {
            const gs = L.geoJSON(geojson).addTo(fg)
            gs.bindPopup(layer => { return layer.feature.properties.name })
            const bounds = fg.getBounds()
            if (bounds.isValid()) {
                map.fitBounds(fg.getBounds())
            }
        })
        .catch(_ => console.log('invalid geojson'))
}

window.createDatasetMap = createDatasetMap
