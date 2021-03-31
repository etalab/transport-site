import L from 'leaflet'
import Papa from 'papaparse'

/**
 * Represents a Mapbox object.
 * @type {Object}
 */
const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/istopopoki/ckg98kpoc010h19qusi9kxcct/tiles/256/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoiaXN0b3BvcG9raSIsImEiOiJjaW12eWw2ZHMwMGFxdzVtMWZ5NHcwOHJ4In0.VvZvyvK0UaxbFiAtak7aVw',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20
}

// possible field names in csv files
const latLabels = ['Lat', 'Ylat', 'Ylatitude']
const lonLabels = ['Lng', 'Xlong', 'Xlongitude']
const namesLabel = ['Nom', 'nom_lieu', 'nom', 'n_station']

function getLabel (obj, labelsList) {
    for (const label of labelsList) {
        if (Object.keys(obj).indexOf(label) >= 0) {
            return label
        }
    }
    return undefined
}

function initilizeMap (id) {
    const map = L.map(id, { preferCanvas: true }).setView([46.505, 2], 5)
    L.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom
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
            try {
                L.circleMarker([m[latField], m[lonField]], markerOptions)
                    .bindPopup(m[nameField])
                    .addTo(fg)
            } catch (error) {
                console.log('There is some invalid lat/lon data in the file')
            }
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

function createCSVmap (id, resourceUrl) {
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

function setGBFSMarkerStyle (stations, stationStatus, field) {
    let marker
    if (field === 'num_bikes_available') {
        marker = stations[stationStatus.station_id].bike
    } else if (field === 'num_docks_available') {
        marker = stations[stationStatus.station_id].spot
    }
    if (stationStatus.is_renting !== true && stationStatus.is_renting !== 1) {
        marker
            .unbindTooltip()
            .bindTooltip('HS', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillColor: 'red' })
    } else {
        const bikesN = stationStatus[field]
        let opacity = 0.8
        if (bikesN === 0) {
            opacity = 0.4
        } else if (bikesN < 3) {
            opacity = 0.6
        }
        marker
            .unbindTooltip()
            .bindTooltip(`${bikesN}`, { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillOpacity: opacity })
    }
    marker.bindPopup(JSON.stringify(stationStatus, null, '<br>&ensp;&ensp;').replace('}', '<br>}'))
}

function fillGBFSMap (resourceUrl, fg, availableDocks, map, fitBounds = false) {
    let stationStatusUrl
    const stations = {}
    fetch(resourceUrl)
        .then(response => response.json())
        .then(gbfs => {
            const feeds = gbfs.data.fr.feeds
            const stationInformation = feeds.filter(feed => feed.name === 'station_information')[0]
            const stationInformationUrl = stationInformation.url
            const stationStatus = feeds.filter(feed => feed.name === 'station_status')[0]
            stationStatusUrl = stationStatus.url
            return fetch(stationInformationUrl)
        })
        .then(data => data.json())
        .then(stationInformation => {
            fg.clearLayers()
            availableDocks.clearLayers()
            for (const station of stationInformation.data.stations) {
                const markerBike = L.circleMarker([station.lat, station.lon], { stroke: false, color: '#0066db', fillOpacity: 0.8 })
                    .bindTooltip('&#x21bb', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
                    .addTo(fg)
                const markerSpot = L.circleMarker([station.lat, station.lon], { stroke: false, color: '#009c34', fillOpacity: 0.8 })
                    .bindTooltip('&#x21bb', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
                    .addTo(availableDocks)
                stations[station.station_id] = { bike: markerBike, spot: markerSpot }
            }
            if (fitBounds) {
                map.fitBounds(fg.getBounds())
            }
        })
        .then(() => fetch(stationStatusUrl))
        .then(response => response.json())
        .then(status => {
            for (const station of status.data.stations) {
                setGBFSMarkerStyle(stations, station, 'num_bikes_available')
                setGBFSMarkerStyle(stations, station, 'num_docks_available')
            }
        })
        .catch(_ => console.log('invalid geojson'))
}

function createGBFSmap (id, resourceUrl) {
    const { map, fg } = initilizeMap(id)
    const availableDocks = L.featureGroup()
    L.control.layers({ 'vélos disponibles': fg, 'places disponibles': availableDocks }, {}, { collapsed: false }).addTo(map)

    fillGBFSMap(resourceUrl, fg, availableDocks, map, true)
    setInterval(() => fillGBFSMap(resourceUrl, fg, availableDocks, map), 60000)
}

function createMap (id, resourceUrl) {
    if (resourceUrl.endsWith('.csv')) {
        createCSVmap(id, resourceUrl)
    } else if (resourceUrl.endsWith('gbfs.json')) {
        createGBFSmap(id, resourceUrl)
    }
}

window.createMap = createMap
