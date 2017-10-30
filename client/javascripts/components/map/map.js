import Leaflet from 'leaflet'

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
    const map   = Leaflet.map(id).setView([51.505, -0.09], 13)
    const popup = `<a class="${opts.linkClass}" role="link" href="${opts.linkHref}">${opts.linkText}</a>`

    Leaflet.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        id: Mapbox.id
    }).addTo(map)

    fetch(featuresUrl) // eslint-disable-line no-undef
        .then(response => { return response.json() })
        .then(data => {
            const geoJSON = Leaflet.geoJSON(data, {
                pointToLayer: (feature, latlng) => {
                    if (!feature.properties.has_data) { return }

                    return Leaflet.circleMarker(latlng, {
                        color: '#1CB841',
                        fillColor: '#1CB841',
                        fillOpacity: 0.25,
                        radius: 25
                    }).bindPopup(popup)
                }
            })

            geoJSON.addTo(map)
            map.fitBounds(geoJSON.getBounds())
        })

    return map
}
