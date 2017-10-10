import Leaflet from 'leaflet'
import 'leaflet.markercluster'

/**
 * Represents a Mapbox object.
 * @type {Object}
 */
const Mapbox = {
    url: 'https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoibC12aW5jZW50LWwiLCJhIjoiaDJfM05UMCJ9.l9oR075SSzJY9hXEqaRvoQ',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 18,
    id: 'mapbox.streets'
}

/**
 * Initialises a map.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} featuresUrl Url exposing a {FeatureCollection}.
 */
export const addMap = (id, featuresUrl, opts) => {
    const map     = Leaflet.map(id).setView([51.505, -0.09], 13)
    const cluster = Leaflet.markerClusterGroup()

    const features = (data) => {
        return {
            'type': 'FeatureCollection',
            'features': data.map(dataset => {
                return {
                    'geometry': {
                        'type': 'Point',
                        'coordinates': dataset.attributes.coordinates
                    },
                    'properties': {
                        'title': dataset.attributes.title,
                        'link': dataset.links.self
                    },
                    'type': 'Feature'
                }
            })
        }
    }

    Leaflet.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        id: Mapbox.id
    }).addTo(map)

    fetch(featuresUrl)
        .then(response => { return response.json() })
        .then(response => {
            const geoJSON = Leaflet.geoJSON(features(response.data), {
                pointToLayer: (feature, latlng) => {
                    return Leaflet.circleMarker(latlng, {
                        color: '#B5E28C',
                        opacity: 0.6,
                        fillColor: '#6ECC39',
                        fillOpacity: 0.7,
                        weight: 10,
                        radius: 13
                    }).bindPopup(
                        `<a class="${opts.linkClass}" role="link" href="${feature.properties.link}">
                            ${feature.properties.title}
                        </a>`
                    )
                }
            })

            cluster.addLayer(geoJSON)
            map.addLayer(cluster)
            map.fitBounds(geoJSON.getBounds())
        })

    return map
}
