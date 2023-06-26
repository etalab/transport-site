import L from 'leaflet'
import { Mapbox } from './mapbox-credentials'

function initilizeMap (id) {
    const map = L.map(id, { renderer: L.canvas() }).setView([46.505, 2], 5)
    L.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        tileSize: Mapbox.tileSize,
        zoomOffset: Mapbox.zoomOffset
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
