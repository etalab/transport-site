import L from 'leaflet'

/**
 * Represents a Mapbox object.
 * @type {Object}
 */
const Mapbox = {
    url: 'https://api.mapbox.com/styles/v1/transport-pan/clj8j9fla009701pie4nrfo62/tiles/{tileSize}/{z}/{x}/{y}?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoidHJhbnNwb3J0LXBhbiIsImEiOiJjbGo4anJodWUxOXY0M3BxeWo3bHlrMXoxIn0.qFfjiswVf2TaLQ2YmB-Mnw',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 20,
    tileSize: 512,
    zoomOffset: -1
}

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

function getColor (severity) {
    const severityColor = {
        Error: 'red',
        Warning: '#ff6600',
        Information: 'orange'
    }
    return severityColor[severity] || 'blue'
}

function createValidationMap (divId, dataVis) {
    const { map, fg } = initilizeMap(divId)
    const gs = L.geoJSON(dataVis.geojson, {
        pointToLayer (feature, latlng) {
            const marker = L.circleMarker(latlng, { radius: 5, fillColor: 'white', fillOpacity: 1, color: getColor(dataVis.severity) })
            marker.addTo(fg)
            return marker
        },
        style (feature) {
            if (feature.geometry.type === 'Point') {
                return {}
            } else {
                return {
                    color: 'black'
                }
            }
        },
        onEachFeature (feature, layer) {
            layer.on('mouseover', () => { layer.setStyle({ weight: 5, radius: 7 }) })
            layer.on('mouseout', () => { layer.setStyle({ weight: 3, radius: 5 }) })
        }
    }).addTo(map)
    fg.bringToFront()
    gs.bindPopup(layer => {
        let popupContent = layer.feature.properties.name || layer.feature.properties.details
        if (layer.feature.properties.id) {
            popupContent += `<br>ID ${layer.feature.properties.id}`
        }
        return popupContent
    })
    const bounds = fg.getBounds()
    if (bounds.isValid()) {
        map.fitBounds(fg.getBounds())
    }
}

window.createValidationMap = createValidationMap
