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

    const markersfg = L.featureGroup().addTo(map)
    const linesfg = L.featureGroup().addTo(map)
    return { map, markersfg, linesfg }
}

function setLinesStyle (feature) {
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

function createResourceGeojson (mapDivId, infoDivId, geojsonUrl, filesize = 0, msg1 = '', msg2 = '') {
    const sizeMB = filesize / 1024 / 1024
    const infoDiv = document.getElementById(infoDivId)
    const mapDiv = document.getElementById(mapDivId)

    if (sizeMB > 0.5) {
        // for large files, user has to click to download and see the file
        infoDiv.innerHTML = `<div>${msg1} (${Math.round(sizeMB)} Mo).</div>
            <button class="button" onclick="createResourceGeojson('${mapDivId}', '${infoDivId}', '${geojsonUrl}')">
            ${msg2}
            </button>`
        mapDiv.outerHTML = `<div id="${mapDivId}"></div>`
    } else {
        infoDiv.outerHTML = ''
        mapDiv.outerHTML = `<div id="${mapDivId}" style="height: 400px;"></div>`

        const { map, markersfg, linesfg } = initilizeMap(mapDivId)
        fetch(geojsonUrl)
            .then(data => data.json())
            .then(geojson => {
                const stops = L.geoJSON(geojson, {
                    pointToLayer: createStopsMarkers,
                    style: setLinesStyle,
                    filter: (feature) => feature.geometry.type === 'Point'
                }).addTo(markersfg)

                stops.bindPopup(layer => { return layer.feature.properties.name })

                const lines = L.geoJSON(geojson, {
                    style: setLinesStyle,
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
}

window.createResourceGeojson = createResourceGeojson
