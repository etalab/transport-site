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

let gtfsChannelRef

// Default location is Paris
const DEFAULT_LAT = 48.8575
const DEFAULT_LNG = 2.3514
const DEFAULT_ZOOM = 6

function getMapParamsFromUrlPath () {
    // Example Path: /explore?@34.0522,-118.2437,10
    const path = decodeURIComponent(window.location.search)
    const parts = path.split('@')

    // If there is no '@' segment, return defaults
    if (parts.length < 2) {
        return { lat: DEFAULT_LAT, lng: DEFAULT_LNG, zoom: DEFAULT_ZOOM }
    }

    const coordsStr = parts[1]
    const [latStr, lngStr, zoomStr] = coordsStr.split(',')

    const lat = parseFloat(latStr) || DEFAULT_LAT
    const lng = parseFloat(lngStr) || DEFAULT_LNG

    const zoom = parseInt(zoomStr, 10) || DEFAULT_ZOOM
    return { lat, lng, zoom }
}

const { lat, lng, zoom } = getMapParamsFromUrlPath()
const map = Leaflet.map('map', { renderer: Leaflet.canvas() }).setView([lat, lng], zoom)

Leaflet.tileLayer(Mapbox.url, {
    accessToken: Mapbox.accessToken,
    attribution: Mapbox.attribution,
    maxZoom: Mapbox.maxZoom,
    tileSize: Mapbox.tileSize,
    zoomOffset: Mapbox.zoomOffset
}).addTo(map)

const visibility = { gtfsrt: document.getElementById('gtfs-rt-check').checked }

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

function withQueryParams (alter) {
    const params = new URLSearchParams(window.location.search)
    alter(params)
    const newurl = window.location.protocol + '//' + window.location.host + window.location.pathname + '?' + params.toString()
    window.history.pushState({ path: newurl }, '', newurl)
}

function setQueryFlag (key) {
    withQueryParams(params => params.set(key, 'yes'))
}

function setQueryParam (key, value) {
    withQueryParams(params => params.set(key, value))
}

function unsetQueryFlag (key) {
    withQueryParams(params => params.delete(key))
}

// handle GTFS-RT toggle
const gtfsrtCheckbox = document.getElementById('gtfs-rt-check')
gtfsrtCheckbox.addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('gtfs-rt')
        startGTFSRT()
    } else {
        unsetQueryFlag('gtfs-rt')
        stopGTFSRT()
    }
})

function startGTFSRT () {
    visibility.gtfsrt = true

    gtfsChannelRef = channel.on('vehicle-positions', payload => {
        if (payload.error) {
            console.log(`Resource ${payload.resource_id} failed to load`)
        } else {
            layers.gtfsrt[payload.resource_id] = prepareLayer(payload.resource_id, payload.vehicle_positions)
            deckGLLayer.setProps({ layers: getLayers(layers) })
        }
    })
}

function stopGTFSRT () {
    visibility.gtfsrt = false
    channel.off('vehicle-positions', gtfsChannelRef)
    for (const key in layers.gtfsrt) {
        layers.gtfsrt[key] = prepareLayer(key, [])
    }
    deckGLLayer.setProps({ layers: getLayers(layers) })
}

// Handle BNLC toggle
document.getElementById('bnlc-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('bnlc')
        startBNLC()
    } else {
        unsetQueryFlag('bnlc')
        updateBNLCLayer(null)
    }
})

function startBNLC () {
    trackEvent('bnlc')
    fetch('/api/geo-query?data=bnlc')
        .then(data => updateBNLCLayer(data.json()))
}

// Handle Parkings Relais toggle
document.getElementById('parkings_relais-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('parkings-relais')
        startParkingsRelais()
    } else {
        unsetQueryFlag('parkings-relais')
        updateParkingsRelaisLayer(null)
    }
})

function startParkingsRelais () {
    trackEvent('parkings-relais')
    fetch('/api/geo-query?data=parkings_relais')
        .then(data => updateParkingsRelaisLayer(data.json()))
}

// Handle ZFE toggle
document.getElementById('zfe-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('zfe')
        startZFE()
    } else {
        unsetQueryFlag('zfe')
        updateZFELayer(null)
    }
})

function startZFE () {
    trackEvent('zfe')
    fetch('/api/geo-query?data=zfe')
        .then(data => updateZFELayer(data.json()))
}

// Handle IRVE toggle
document.getElementById('irve-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('irve')
        startIRVE()
    } else {
        unsetQueryFlag('irve')
        updateIRVELayer(null)
    }
})

function startIRVE () {
    trackEvent('irve')
    fetch('/api/geo-query?data=irve')
        .then(data => updateIRVELayer(data.json()))
}

// Handle GBFS stations toggle
document.getElementById('gbfs_stations-check').addEventListener('change', (event) => {
    if (event.currentTarget.checked) {
        setQueryFlag('gbfs-stations')
        startGBFS()
    } else {
        unsetQueryFlag('gbfs-stations')
        updateGBFSStationsLayer(null)
    }
})

function startGBFS () {
    trackEvent('gbfs-stations')
    fetch('/api/geo-query?data=gbfs_stations')
        .then(data => updateGBFSStationsLayer(data.json()))
}

const bootSequence = {
    'gtfs-rt-check': startGTFSRT,
    'bnlc-check': startBNLC,
    'parkings_relais-check': startParkingsRelais,
    'zfe-check': startZFE,
    'irve-check': startIRVE,
    'gbfs_stations-check': startGBFS
}

// make sure the checkboxes status is in sync when loading from query params
document.addEventListener('DOMContentLoaded', () => {
    for (const checkId in bootSequence) {
        if (document.getElementById(checkId).checked) {
            bootSequence[checkId]()
        }
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

function updateUrl () {
    const center = map.getCenter()
    const zoom = map.getZoom()

    const lat = center.lat.toFixed(5)
    const lng = center.lng.toFixed(5)
    const z = zoom

    const params = `${lat},${lng},${z}`
    setQueryParam('@', params)
}

map.on('moveend', updateUrl)

// Autocomplete
document.querySelector('#autoComplete').addEventListener('selection', function (event) {
    event.preventDefault()
    map.flyTo([event.detail.selection.value.y, event.detail.selection.value.x], 12)
})

export default socket
