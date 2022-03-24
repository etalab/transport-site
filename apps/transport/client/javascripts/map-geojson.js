import L from 'leaflet'

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

function initilizeMap (id) {
    const map = L.map(id, { renderer: L.canvas() }).setView([46.505, 2], 5)
    L.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom
    }).addTo(map)

    const markersfg = L.featureGroup().addTo(map)
    const linesfg = L.featureGroup().addTo(map)
    return { map, markersfg, linesfg }
}

function GTFSLinesStyle (feature) {
    if (feature.geometry.type !== 'Point') {
        return { color: feature.properties.route_color, weight: 5 }
    } else {
        return {}
    }
}

function createStopsMarkers (geoJsonPoint, latlng) {
    return L.circleMarker(latlng, { fillColor: 'white', color: 'black', fillOpacity: 1, weight: 3, radius: 5 })
}

function setZoomEvents (map, fg) {
    map.on('zoomend', () => {
        if (map.getZoom() >= 14) {
            fg.setStyle({ fillColor: 'white', color: 'black', fillOpacity: 1, weight: 3, radius: 5 })
        } else {
            fg.setStyle({ fillColor: 'white', color: 'black', fillOpacity: 1, weight: 1, radius: 2 })
        }
    })
}

function GeojsonMap (fillMapFunction, mapDivId, infoDivId, geojsonUrl, filesize, msg1, msg2) {
    const sizeMB = filesize / 1024 / 1024
    const infoDiv = document.getElementById(infoDivId)
    const mapDiv = document.getElementById(mapDivId)

    if (sizeMB > 2) {
        // for large files, user has to click to download and see the file
        infoDiv.innerHTML = `<div>${msg1} (${Math.round(sizeMB)} Mo).</div>
            <button class="button">
            ${msg2}
            </button>`
        infoDiv.addEventListener('click', function () {
            // show anyway
            GeojsonMap(fillMapFunction, mapDivId, infoDivId, geojsonUrl, 0, msg1, msg2)
        })
        mapDiv.outerHTML = `<div id="${mapDivId}"></div>`
    } else {
        infoDiv.outerHTML = ''
        mapDiv.outerHTML = `<div id="${mapDivId}" style="height: 600px; max-height: 80vh;"></div>`
        fillMapFunction(mapDivId, geojsonUrl)
    }
}

function GTFSMap (mapDivId, geojsonUrl) {
    const { map, markersfg, linesfg } = initilizeMap(mapDivId)
    fetch(geojsonUrl)
        .then(data => data.json())
        .then(geojson => {
            const stops = L.geoJSON(geojson, {
                pointToLayer: createStopsMarkers,
                style: GTFSLinesStyle,
                filter: (feature) => feature.geometry.type === 'Point'
            }).addTo(markersfg)

            stops.bindPopup(layer => { return layer.feature.properties.name })

            const lines = L.geoJSON(geojson, {
                style: GTFSLinesStyle,
                filter: (feature) => feature.geometry.type !== 'Point'
            }).addTo(linesfg)

            lines.bindPopup(layer => { return layer.feature.properties.route_long_name })

            lines.bringToBack()
            stops.bringToFront()

            setZoomEvents(map, stops)

            const bounds = markersfg.getBounds()
            if (bounds.isValid()) {
                map.fitBounds(markersfg.getBounds())
            }
        })
        .catch(_ => console.log('invalid geojson'))
}

function GenericLinesStyle (feature) {
    return { weight: 3 }
}

function createPointsMarkers (geoJsonPoint, latlng) {
    return L.circleMarker(latlng, { stroke: false, color: '#0066db', fillOpacity: 0.7 })
}

function formatPopupContent (content) {
    return `<pre>${JSON.stringify(content, null, 2)}</pre>`
}

function GenericMap (mapDivId, geojsonUrl) {
    const { map, markersfg, linesfg } = initilizeMap(mapDivId)
    fetch(geojsonUrl)
        .then(data => data.json())
        .then(geojson => {
            const markers = L.geoJSON(geojson, {
                pointToLayer: createPointsMarkers,
                filter: (feature) => feature.geometry.type === 'Point'
            }).addTo(markersfg)

            markers.bindPopup(layer => formatPopupContent(layer.feature.properties))

            const lines = L.geoJSON(geojson, {
                style: GenericLinesStyle,
                filter: (feature) => feature.geometry.type !== 'Point'
            }).addTo(linesfg)

            lines.bindPopup(layer => { return formatPopupContent(layer.feature.properties) })

            lines.bringToBack()
            markers.bringToFront()

            if (linesfg.getBounds().isValid()) {
                map.fitBounds(linesfg.getBounds())
            } else if (markersfg.getBounds().isValid()) {
                map.fitBounds(markersfg.getBounds())
            }
        })
        .catch(_ => console.log('invalid geojson'))
}

function GTFSGeojsonMap (mapDivId, infoDivId, geojsonUrl, filesize = 0, msg1 = '', msg2 = '') {
    GeojsonMap(GTFSMap, mapDivId, infoDivId, geojsonUrl, filesize, msg1, msg2)
}

function GenericGeojsonMap (mapDivId, infoDivId, geojsonUrl, filesize = 0, msg1 = '', msg2 = '') {
    GeojsonMap(GenericMap, mapDivId, infoDivId, geojsonUrl, filesize, msg1, msg2)
}

window.GTFSGeojsonMap = GTFSGeojsonMap
window.GenericGeojsonMap = GenericGeojsonMap
