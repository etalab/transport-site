import { Socket } from 'phoenix'
import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer, GeoJsonLayer } from '@deck.gl/layers'

import { MapView } from '@deck.gl/core'
import { Mapbox } from './map-config'

const socket = new Socket('/socket', { params: { token: window.userToken } })
socket.connect()
const channel = socket.channel('explore', {})
channel.join()
    .receive('ok', resp => { console.log('Joined successfully', resp) })
    .receive('error', resp => { console.log('Unable to join', resp) })

const metropolitanFranceBounds = [[51.1, -4.9], [41.2, 9.8]]
const map = Leaflet.map('map', { renderer: Leaflet.canvas() }).fitBounds(metropolitanFranceBounds)

Leaflet.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom,
    tileSize: Mapbox.tileSize,
    zoomOffset: Mapbox.zoomOffset
}).addTo(map)

const visibility = { gtfsrt: true }

function prepareLayer (layerId, layerData) {
    return new ScatterplotLayer({
        id: layerId,
        data: layerData,
        pickable: true,
        opacity: 1,
        stroked: false,
        filled: true,
        radiusMinPixels: 4,
        radiusMaxPixels: 10,
        lineWidthMinPixels: 1,
        visible: visibility.gtfsrt,
        getPosition: d => {
            return [d.position.longitude, d.position.latitude]
        },
        getRadius: d => 1000,
        getFillColor: d => [0, 150, 136, 150],
        getLineColor: d => [0, 150, 136]
    })
}

const deckGLLayer = new LeafletLayer({
    views: [new MapView({ repeat: true })],
    layers: [],
    getTooltip
})
map.addLayer(deckGLLayer)

function getTooltip ({ object, layer }) {
    if (object) {
        if (layer.id === 'bnlc-layer') {
            return { html: `<strong>Aire de covoiturage</strong><br>${object.properties.nom_lieu}` }
        } else if (layer.id === 'parkings_relais-layer') {
            return { html: `<strong>Parking relais</strong><br>${object.properties.nom}<br>Capacité : ${object.properties.nb_pr} places` }
        } else if (layer.id === 'zfe-layer') {
            return { html: '<strong>Zone à Faible Émission</strong>' }
        } else if (layer.id === 'gbfs_stations-layer') {
            return {
                html: `<strong>Station GBFS</strong><br>
                    ${object.properties.name}<br>
                    Capacité&nbsp;: ${object.properties.capacity}`
            }
        } else if (layer.id === 'irve-layer') {
            return {
                html: `<strong>Infrastructure de recharge</strong><br>
            ${object.properties.nom_station}<br>
            Enseigne&nbsp;: ${object.properties.nom_enseigne}<br>
            Identifiant station en itinérance&nbsp;: ${object.properties.id_station_itinerance}<br>
            Nombre de points de charge&nbsp;: ${object.properties.nbre_pdc}`
            }
        } else {
            return { html: `<strong>Position temps-réel</strong><br>transport_resource: ${object.transport.resource_id}<br>id: ${object.vehicle.id}` }
        }
    }
}
// internal dictionary were all layers are stored
const layers = { gtfsrt: {}, bnlc: undefined, parkings_relais: undefined, zfe: undefined, gbfs_stations: undefined }

function getLayers (layers) {
    const layersArray = Object.values(layers.gtfsrt)
    layersArray.push(layers.bnlc)
    layersArray.push(layers.parkings_relais)
    layersArray.push(layers.zfe)
    layersArray.push(layers.irve)
    layersArray.push(layers.gbfs_stations)
    return layersArray
}

channel.on('vehicle-positions', payload => {
    if (payload.error) {
        console.log(`Resource ${payload.resource_id} failed to load`)
    } else {
        layers.gtfsrt[payload.resource_id] = prepareLayer(payload.resource_id, payload.vehicle_positions)
        deckGLLayer.setProps({ layers: getLayers(layers) })
    }
})

// handle GTFS-RT toggle
const gtfsrtCheckbox = document.getElementById('gtfs-rt-check')
gtfsrtCheckbox.addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        visibility.gtfsrt = true
    } else {
        visibility.gtfsrt = false
        for (const key in layers.gtfsrt) {
            layers.gtfsrt[key] = prepareLayer(key, [])
        }
        deckGLLayer.setProps({ layers: getLayers(layers) })
    }
})

// Handle BNLC toggle
document.getElementById('bnlc-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        trackEvent('bnlc')
        fetch('/api/geo-query?data=bnlc')
            .then(data => updateBNLCLayer(data.json()))
    } else {
        updateBNLCLayer(null)
    }
})

// Handle Parkings Relais toggle
document.getElementById('parkings_relais-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        trackEvent('parkings-relais')
        fetch('/api/geo-query?data=parkings_relais')
            .then(data => updateParkingsRelaisLayer(data.json()))
    } else {
        updateParkingsRelaisLayer(null)
    }
})

// Handle ZFE toggle
document.getElementById('zfe-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        trackEvent('zfe')
        fetch('/api/geo-query?data=zfe')
            .then(data => updateZFELayer(data.json()))
    } else {
        updateZFELayer(null)
    }
})

// Handle IRVE toggle
document.getElementById('irve-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        trackEvent('irve')
        fetch('/api/geo-query?data=irve')
            .then(data => updateIRVELayer(data.json()))
    } else {
        updateIRVELayer(null)
    }
})

// Handle GBFS stations toggle
document.getElementById('gbfs_stations-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        trackEvent('gbfs-stations')
        fetch('/api/geo-query?data=gbfs_stations')
            .then(data => updateGBFSStationsLayer(data.json()))
    } else {
        updateGBFSStationsLayer(null)
    }
})

function updateBNLCLayer (geojson) {
    layers.bnlc = createPointsLayer(geojson, 'bnlc-layer')
    deckGLLayer.setProps({ layers: getLayers(layers) })
}
function updateParkingsRelaisLayer (geojson) {
    layers.parkings_relais = createPointsLayer(geojson, 'parkings_relais-layer')
    deckGLLayer.setProps({ layers: getLayers(layers) })
}
function updateZFELayer (geojson) {
    layers.zfe = createPointsLayer(geojson, 'zfe-layer')
    deckGLLayer.setProps({ layers: getLayers(layers) })
}
function updateIRVELayer (geojson) {
    layers.irve = createPointsLayer(geojson, 'irve-layer')
    deckGLLayer.setProps({ layers: getLayers(layers) })
}
function updateGBFSStationsLayer (geojson) {
    layers.gbfs_stations = createPointsLayer(geojson, 'gbfs_stations-layer')
    deckGLLayer.setProps({ layers: getLayers(layers) })
}

function trackEvent (layer) {
    // https://matomo.org/faq/reports/implement-event-tracking-with-matomo/#how-to-set-up-matomo-event-tracking-with-javascript
    // `window._paq` is only defined in production (in templates/layout/app.html.heex)
    if (window._paq) {
        window._paq.push(['trackEvent', 'explore-map', 'enable-layer', layer])
    }
}

function createPointsLayer (geojson, id) {
    const fillColor = {
        'bnlc-layer': [255, 174, 0, 100],
        'parkings_relais-layer': [0, 33, 70, 100],
        'zfe-layer': [52, 8, 143, 100],
        'irve-layer': [245, 40, 145, 100],
        'gbfs_stations-layer': [60, 115, 168, 100]
    }[id]

    return new GeoJsonLayer({
        id,
        data: geojson,
        pickable: true,
        stroked: false,
        filled: true,
        extruded: false,
        pointType: 'circle',
        opacity: 1,
        getFillColor: fillColor,
        getPointRadius: 1000,
        pointRadiusUnits: 'meters',
        pointRadiusMinPixels: 2,
        pointRadiusMaxPixels: 10,
        visible: geojson !== null
    })
}

export default socket
