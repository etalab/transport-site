import Leaflet from 'leaflet'

/**
 * Represents a Mapbox object.
 * @type {Object}
 */
const Mapbox = {
    url: 'https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token={accessToken}',
    accessToken: 'pk.eyJ1IjoibC12aW5jZW50LWwiLCJhIjoiY2pzMWtlNG90MXA5cTQ5dGYwNDRyMDRvayJ9.RhYAa9O0Qla5zhJAb9iwJA',
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors <a href="https://spdx.org/licenses/ODbL-1.0.html">ODbL</a>, Imagery © <a href="http://mapbox.com">Mapbox</a>',
    maxZoom: 18,
    id: 'mapbox.streets'
}

/**
 * Initialises a map.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
export default function (id, aomsUrl, regionsUrl) {
    const map = Leaflet.map(id).setView([46.370, 2.087], 5)
    map.createPane('aoms')
    map.getPane('aoms').style.zIndex = 650

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const count = feature.properties.dataset_count
        const text = count === 0 ? 'Aucun jeu de données'
            : count === 1 ? 'Un jeu de données'
                : `${count} jeux de données`
        const extra = feature.properties.parent_dataset_slug !== null
            ? `<br>Données incluses dans le jeu de données <a href="/datasets/${feature.properties.parent_dataset_slug}/">${feature.properties.parent_dataset_name}</a>`
            : ''
        const commune = feature.properties.id
        layer.bindPopup(`<strong>${name}</strong><br/>${type}<br/><a href="/datasets/aom/${commune}">${text}</a>${extra}`)
    }

    function onEachRegionFeature (feature, layer) {
        const name = feature.properties.nom
        const id = feature.properties.id
        const count = feature.properties.dataset_count
        const text = count === 0 ? 'Aucun jeu de données'
            : count === 1 ? 'Un jeu de données'
                : `${count} jeux de données`
        layer.bindPopup(`<strong>${name}</strong><br/><a href="/datasets/region/${id}">${text}</a>`)
    }

    const styles = {
        unavailable: {
            weight: 1,
            color: 'grey'
        },
        available: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.5
        },
        availableElsewhere: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.1,
            dashArray: '4 1'
        }
    }

    const style = feature => {
        if (feature.properties.dataset_count > 0) {
            return styles.available
        } else if (feature.properties.parent_dataset_slug) {
            return styles.availableElsewhere
        } else {
            return styles.unavailable
        }
    }

    const regionStyles = {
        completed: {
            weight: 2,
            color: 'green'
        },
        partial: {
            weight: 1,
            color: 'orange'
        },
        unavailable: {
            stroke: false,
            fill: false
        }
    }

    const styleRegion = feature => {
        if (feature.properties.completed) {
            return regionStyles.completed
        }
        if (feature.properties.dataset_count === 0) {
            return regionStyles.unavailable
        } else {
            return regionStyles.partial
        }
    }

    Leaflet.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        id: Mapbox.id
    }).addTo(map)

    fetch(regionsUrl)
        .then(response => { return response.json() })
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: onEachRegionFeature,
                style: styleRegion
            })
            map.addLayer(geoJSON)
        })

    fetch(aomsUrl)
        .then(response => { return response.json() })
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: onEachAomFeature,
                style: style,
                pane: 'aoms'
            })
            map.addLayer(geoJSON)
        })

    const legend = Leaflet.control({ position: 'bottomright' })
    legend.onAdd = function (map) {
        const div = Leaflet.DomUtil.create('div', 'info legend')
        const colors = ['green', 'orange', 'grey']
        const labels = ['Données disponible', 'Données partiellement disponible', 'Aucune donnée disponible']

        div.innerHTML += '<h4>Disponibilité des horaires théoriques</h4>'
        // loop through our density intervals and generate a label with a colored square for each interval
        for (var i = 0; i < colors.length; i++) {
            div.innerHTML += `<i style="background:${colors[i]}"></i>${labels[i]}<br/>`
        }

        return div
    }

    legend.addTo(map)

    return map
}
