import L from 'leaflet'
import Papa from 'papaparse'

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

// possible field names in csv files
const latLabels = ['Lat', 'Ylat']
const lonLabels = ['Lng', 'Xlong']
const namesLabel = ['Nom', 'nom_lieu', 'nom']

function getLabel (obj, labelsList) {
    for (const label of labelsList) {
        if (Object.keys(obj).indexOf(label) >= 0) {
            return label
        }
    }
    return undefined
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

function displayData (data, fg, { latField, lonField, nameField }) {
    const markerOptions = {
        fillColor: '#0066db',
        radius: 5,
        stroke: false,
        fillOpacity: 0.15
    }
    for (const m of data) {
        if (m[latField] && m[lonField]) {
            L.circleMarker([m[latField], m[lonField]], markerOptions)
                .bindPopup(m[nameField])
                .addTo(fg)
        }
    }
}

function setZoomEvents (map, fg) {
    map.on('zoomend', () => {
        if (map.getZoom() > 12) {
            fg.setStyle({ fillOpacity: 0.4, radius: 10 })
        } else if (map.getZoom() > 8) {
            fg.setStyle({ fillOpacity: 0.3, radius: 5 })
        } else {
            fg.setStyle({ fillOpacity: 0.15, radius: 5 })
        }
    })
}

function createMap (id, resourceUrl) {
    Papa.parse(resourceUrl, {
        download: true,
        header: true,
        complete: function (data) {
            const latField = getLabel(data.data[0], latLabels)
            const lonField = getLabel(data.data[0], lonLabels)
            const nameField = getLabel(data.data[0], namesLabel)
            if (latField && lonField && nameField) {
                const { map, fg } = initilizeMap(id)
                displayData(data.data, fg, { latField, lonField, nameField })
                map.fitBounds(fg.getBounds())
                setZoomEvents(map, fg)
            }
        }
    })
}

window.createMap = createMap
