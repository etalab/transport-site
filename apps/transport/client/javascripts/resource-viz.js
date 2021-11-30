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

function coordinatesAreCorrect (lat, lon) {
    return !isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

function displayData (data, fg, { latField, lonField, nameField }) {
    const markerOptions = {
        fillColor: '#0066db',
        radius: 5,
        stroke: false,
        fillOpacity: 0.15
    }
    for (const m of data) {
        if (coordinatesAreCorrect(m[latField], m[lonField])) {
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
            } else {
                removeViz('vizualisation of the resource has failed : not recognized column names')
            }
        }
    })
}

function setGBFSStationStyle (feature, layer, field) {
    const stationStatus = feature.properties.station_status

    if (stationStatus.is_renting !== true && stationStatus.is_renting !== 1) {
        layer
            .unbindTooltip()
            .bindTooltip('HS', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillColor: 'red' })
    } else {
        const N = stationStatus[field]
        let opacity = 0.8
        if (N === 0) {
            opacity = 0.4
        } else if (N < 3) {
            opacity = 0.6
        }
        layer
            .unbindTooltip()
            .bindTooltip(`${N}`, { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillOpacity: opacity })
    }
    layer.bindPopup(`<pre>${JSON.stringify(stationStatus, null, 2)}</pre>`)
}

function setGBFSFreeFloatingStyle (feature, layer) {
    const properties = feature.properties

    if (properties.is_disabled) {
        layer
            .unbindTooltip()
            .bindTooltip('D', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillColor: 'red' })
    } else if (properties.is_reserved) {
        layer
            .unbindTooltip()
            .bindTooltip('R', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillColor: 'orange' })
    } else {
        layer
            .unbindTooltip()
            .bindTooltip('F', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            .setStyle({ fillColor: 'blue' })
    }
    layer.bindPopup(`<pre>${JSON.stringify(properties, null, 2)}</pre>`)
}

function setGBFSGeofencingStyle (feature, layer) {
    const rules = feature.properties.rules
    const rule = rules.length > 0 ? rules[0] : undefined
    let color, opacity

    if (rule) {
        if (rule.ride_through_allowed === false) {
            color = 'red'
            opacity = 0.6
        } else if (rule.ride_allowed === false) {
            color = 'orange'
            opacity = 0.6
        } else {
            color = 'green'
            opacity = 0.4
        }
    }
    layer
        .bindPopup(`<pre>${JSON.stringify(feature.properties, null, 2)}</pre>`)
        .setStyle({ fillColor: color, color: color, fillOpacity: opacity, stroke: false })
}

function fillStations (stationsGeojson, bikesAvailable, docksAvailable) {
    L.geoJSON(stationsGeojson, {
        pointToLayer: function (geoJsonPoint, latlng) {
            return L.circleMarker(latlng, { stroke: false, color: '#0066db', fillOpacity: 0.8 })
        },
        onEachFeature: (feature, layer) => setGBFSStationStyle(feature, layer, 'num_bikes_available')
    }).addTo(bikesAvailable)

    L.geoJSON(stationsGeojson, {
        pointToLayer: function (geoJsonPoint, latlng) {
            return L.circleMarker(latlng, { stroke: false, color: '#009c34', fillOpacity: 0.8 })
        },
        onEachFeature: (feature, layer) => setGBFSStationStyle(feature, layer, 'num_docks_available')
    }).addTo(docksAvailable)
}

function clearFeatureGroups (featureGroups) {
    for (const fg in featureGroups) {
        featureGroups[fg].clearLayers()
    }
}

function fillFreeFloating (geojson, freeFloating) {
    L.geoJSON(geojson, {
        pointToLayer: function (geoJsonPoint, latlng) {
            return L.circleMarker(latlng, { stroke: false, color: '#0066db', fillOpacity: 0.7 })
        },
        onEachFeature: (feature, layer) => setGBFSFreeFloatingStyle(feature, layer)
    }).addTo(freeFloating)
}

function fillGeofencingZones (geojson, geoFencingZones) {
    L.geoJSON(geojson, {
        onEachFeature: (feature, layer) => setGBFSGeofencingStyle(feature, layer)
    }).addTo(geoFencingZones)
}

function fillGBFSMap (resourceUrl, fg, map, firstCall = false) {
    const geojsonUrl = `/tools/gbfs/geojson_convert?url=${resourceUrl}`
    fetch(geojsonUrl)
        .then(response => response.json())
        .then(data => {
            clearFeatureGroups(fg)

            if ('stations' in data) {
                fg.bikesAvailable = fg.bikesAvailable ? fg.bikesAvailable : L.featureGroup()
                fg.docksAvailable = fg.docksAvailable ? fg.docksAvailable : L.featureGroup()
                fillStations(data.stations, fg.bikesAvailable, fg.docksAvailable)
            }

            if ('free_floating' in data) {
                fg.freeFloating = fg.freeFloating ? fg.freeFloating : L.featureGroup()
                fillFreeFloating(data.free_floating, fg.freeFloating)
            }

            if ('geofencing_zones' in data) {
                fg.geofencingZones = fg.geofencingZones ? fg.geofencingZones : L.featureGroup()
                fillGeofencingZones(data.geofencing_zones, fg.geofencingZones)
            }

            setGBFSLayersControl(fg, map)
            if (firstCall) {
                // add one of the feature to the map (initial state)
                const firstFg = fg[Object.keys(fg)[0]]
                firstFg.addTo(map)
                map.fitBounds(firstFg.getBounds())
            }
        })
        .catch(e => removeViz(e))
}

// we want a custom message on the layers toggle control, depending on the GBFS vehicle type
function setGBFSLayersControl (/* feeds, */fg, map) {
    if (!map.controlLayers) {
        const control = {}
        if ('bikesAvailable' in fg) {
            control['Véhicules disponibles'] = fg.bikesAvailable
        }
        if ('docksAvailable' in fg) {
            control['Places disponibles'] = fg.docksAvailable
        }
        if ('freeFloating' in fg) {
            control['Véhicules free-floating'] = fg.freeFloating
        }
        if ('geofencingZones' in fg) {
            control.Geofencing = fg.geofencingZones
        }
        map.controlLayers = L.control.layers(control, {}, { collapsed: false }).addTo(map)
    }
}

function addCountdownDiv (id, refreshInterval) {
    const node = document.createElement('div')
    node.style.position = 'relative'
    node.style.zIndex = '1000'
    node.style.left = '50%'
    node.id = id
    const textnode = document.createTextNode(refreshInterval)
    node.appendChild(textnode)
    document.getElementById('map').appendChild(node)
}

function createGBFSmap (id, resourceUrl) {
    // eslint-disable-next-line no-unused-vars
    const { map, _ } = initilizeMap(id)
    const featureGroups = {}
    const refreshInterval = 60

    addCountdownDiv('coutdown', refreshInterval)
    let countdown = refreshInterval

    fillGBFSMap(resourceUrl, featureGroups, map, true)
    setInterval(() => {
        countdown = refreshInterval
        fillGBFSMap(resourceUrl, featureGroups, map)
    }, refreshInterval * 1000)

    // update the countdown every second
    setInterval(() => {
        document.getElementById('coutdown').innerHTML = (countdown-- <= 3 ? 'mise à jour' : countdown)
    }, 1000)
}

function createGeojsonMap (id, resourceUrl) {
    const { map, fg } = initilizeMap(id)
    fetch(resourceUrl)
        .then(data => data.json())
        .then(geojson => {
            L.geoJSON(geojson).addTo(fg)
            map.fitBounds(fg.getBounds())
        })
        .catch(e => removeViz(e))
}

function removeViz (consoleMsg) {
    const vis = document.querySelector('#dataset-visualisation')
    if (vis) {
        vis.remove()
    }
    const menu = document.querySelector('#menu-item-visualisation')
    if (menu) {
        menu.remove()
    }
    console.log(consoleMsg)
}

function createMap (id, resourceUrl, resourceFormat) {
    if (resourceUrl.endsWith('.csv')) {
        createCSVmap(id, resourceUrl)
    } else if (resourceFormat === 'gbfs' || resourceUrl.endsWith('gbfs.json')) {
        createGBFSmap(id, resourceUrl)
    } else if (resourceUrl.endsWith('.geojson') || resourceUrl.endsWith('.json')) {
        createGeojsonMap(id, resourceUrl)
    } else {
        removeViz(`vizualisation of the resource ${resourceUrl} has failed : not recognized file extension`)
    }
}

window.createMap = createMap
