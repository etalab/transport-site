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
const latLabels = ['Lat', 'Ylat', 'Ylatitude', 'consolidated_latitude']
const lonLabels = ['Lng', 'Xlong', 'Xlongitude', 'consolidated_longitude']

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

function displayData (data, fg, { latField, lonField }) {
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
                    .bindPopup(`<pre>${JSON.stringify(m, null, 2)}</pre>`)
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
            if (latField && lonField) {
                const { map, fg } = initilizeMap(id)
                displayData(data.data, fg, { latField, lonField })
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

    if (stationStatus) {
        if (stationStatus.is_renting !== true && stationStatus.is_renting !== 1) {
            layer
                .unbindTooltip()
                .bindTooltip('HS', { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
                .setStyle({ fillColor: 'red' })
        } else {
            const N = stationStatus[field] || ''
            let opacity = 0.8
            if (N === 0) {
                opacity = 0.4
            } else if (N < 3) {
                opacity = 0.6
            }
            layer
                .unbindTooltip()
                .setStyle({ fillOpacity: opacity })
            if (N !== '') {
                layer.bindTooltip(`${N}`, { permanent: true, className: 'leaflet-tooltip', direction: 'center' })
            }
        }
        layer.bindPopup(`<pre>${JSON.stringify(stationStatus, null, 2)}</pre>`)
    }
}

function setGBFSFreeFloatingStyle (feature, layer) {
    const properties = feature.properties
    let popupContent

    if (properties.is_disabled) {
        const color = 'red'
        layer
            .unbindTooltip()
            .setStyle({ fillColor: color })
        popupContent = JSON.stringify(properties, null, 2).replace('"is_disabled": true', `<strong class="map-color-${color}">"is_disabled": true</strong>`)
    } else if (properties.is_reserved) {
        const color = 'orange'
        layer
            .unbindTooltip()
            .setStyle({ fillColor: color })
        popupContent = JSON.stringify(properties, null, 2).replace('"is_reserved": true', `<strong class="map-color-${color}">"is_reserved": true</strong>`)
    } else {
        const color = 'blue'
        layer
            .unbindTooltip()
            .setStyle({ fillColor: 'blue' })
        popupContent = JSON.stringify(properties, null, 2)
            .replace('"is_reserved": false', `<strong class="map-color-${color}">"is_reserved": false</strong>`)
            .replace('"is_disabled": false', `<strong class="map-color-${color}">"is_disabled": false</strong>`)
    }
    layer.bindPopup(`<pre>${popupContent}</pre>`)
}

function setGBFSGeofencingStyle (feature, layer) {
    const rules = feature.properties.rules
    const rule = rules.length > 0 ? rules[0] : undefined
    let color, opacity, popupContent

    if (rule) {
        if (rule.ride_through_allowed === false) {
            color = 'red'
            opacity = 0.6
            popupContent = JSON.stringify(feature.properties, null, 2).replace('"ride_through_allowed": false', `<strong class="map-color-${color}">"ride_through_allowed": false</strong>`)
        } else if (rule.ride_allowed === false) {
            color = 'orange'
            opacity = 0.6
            popupContent = JSON.stringify(feature.properties, null, 2).replace('"ride_allowed": false', `<strong class="map-color-${color}">"ride_allowed": false</strong>`)
        } else {
            color = 'green'
            opacity = 0.4
            popupContent = JSON.stringify(feature.properties, null, 2)
                .replace('"ride_through_allowed": true', `<strong class="map-color-${color}">"ride_through_allowed": true</strong>`)
                .replace('"ride_allowed": true', `<strong class="map-color-${color}">"ride_allowed": true</strong>`)
        }
    }
    layer
        .bindPopup(`<pre>${popupContent}</pre>`)
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
    // According to GBFS specification, in case of conflicting rules
    // the first rule in the GeoJSON takes precedence
    // see https://github.com/NABSA/gbfs/blob/v2.2/gbfs.md#geofencing_zonesjson-added-in-v21
    // In leaflet, the last features in the GeoJSON are displayed above the first, so to reflect the spirit of the rule
    // we need to revert the array.
    geojson.features = geojson.features.reverse()

    L.geoJSON(geojson, {
        onEachFeature: (feature, layer) => setGBFSGeofencingStyle(feature, layer)
    }).addTo(geoFencingZones)
}

function fillGBFSMap (resourceUrl, fg, map, lang, firstCall = false) {
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

            setGBFSLayersControl(fg, map, lang)
            if (firstCall) {
                // add one of the feature to the map (initial state)
                const availableLayers = Object.keys(fg)
                if (availableLayers.length <= 0) {
                    throw new Error('No GBFS data can be shown on map')
                }
                const firstFg = fg[availableLayers[0]]

                firstFg.addTo(map)
                map.fitBounds(firstFg.getBounds())
            }
        })
        .catch(e => removeViz(e))
}

// I have removed custom text for vehicle types for the moment.
function setGBFSLayersControl (fg, map, lang) {
    if (!map.controlLayers) {
        const control = {}
        if ('bikesAvailable' in fg) {
            const label = lang === 'fr' ? 'Véhicules disponibles' : 'Available vehicles'
            control[label] = fg.bikesAvailable
        }
        if ('docksAvailable' in fg) {
            const label = lang === 'fr' ? 'Places disponibles' : 'Available docks'
            control[label] = fg.docksAvailable
        }
        if ('freeFloating' in fg) {
            const label = lang === 'fr' ? 'Véhicules free-floating' : 'Free-floating vehicles'
            control[label] = fg.freeFloating
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

function createGBFSmap (id, resourceUrl, lang) {
    // eslint-disable-next-line no-unused-vars
    const { map, _ } = initilizeMap(id)
    const featureGroups = {}
    const refreshInterval = 60

    addCountdownDiv('coutdown', refreshInterval)
    let countdown = refreshInterval

    fillGBFSMap(resourceUrl, featureGroups, map, lang, true)
    setInterval(() => {
        countdown = refreshInterval
        fillGBFSMap(resourceUrl, featureGroups, map, lang, false)
    }, refreshInterval * 1000)

    // update the countdown every second
    const interval = setInterval(() => {
        const el = document.getElementById('coutdown')
        if (el) {
            el.innerHTML = (countdown-- <= 3 ? 'mise à jour' : countdown)
        } else {
            clearInterval(interval)
        }
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

function createMap (id, resourceUrl, resourceFormat, lang = 'fr') {
    if (resourceUrl.endsWith('.csv') || resourceFormat === 'csv') {
        createCSVmap(id, resourceUrl)
    } else if (resourceFormat === 'gbfs' || resourceUrl.endsWith('gbfs.json')) {
        createGBFSmap(id, resourceUrl, lang)
    } else if (resourceUrl.endsWith('.geojson') || resourceUrl.endsWith('.json')) {
        createGeojsonMap(id, resourceUrl)
    } else {
        removeViz(`vizualisation of the resource ${resourceUrl} has failed : not recognized file extension`)
    }
}

window.createMap = createMap
