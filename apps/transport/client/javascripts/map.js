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
    id: 'mapbox.light'
}

const regionsUrl = '/api/stats/regions'
const aomsUrl = '/api/stats/'

const makeMapOnFrance = (id) => {
    const map = Leaflet.map(id).setView([46.370, 2.087], 5)
    map.createPane('aoms')
    map.getPane('aoms').style.zIndex = 650

    Leaflet.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        id: Mapbox.id
    }).addTo(map)

    return map
}

// helper function to add legends
const addLegend = (map, title, colors, labels) => {
    const legend = Leaflet.control({ position: 'bottomright' })
    legend.onAdd = (_map) => {
        const div = Leaflet.DomUtil.create('div', 'info legend')
        div.innerHTML += title
        // loop through our density intervals and generate a label with a colored square for each interval
        for (var i = 0; i < colors.length; i++) {
            div.innerHTML += `<i style="background:${colors[i]}"></i>${labels[i]}<br/>`
        }
        return div
    }

    legend.addTo(map)
}

// simple cache on stats
var aomStats = null
var regionStats = null

function displayAoms (map, featureFunction, style, filter = null) {
    if (aomStats == null) {
        aomStats = fetch(aomsUrl)
            .then(response => { return response.json() })
    }
    aomStats
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: featureFunction,
                style: style,
                filter: filter,
                pane: 'aoms'
            })
            map.addLayer(geoJSON)
        })
}

function displayRegions (map, featureFunction, style) {
    if (regionStats == null) {
        regionStats = fetch(regionsUrl)
            .then(response => { return response.json() })
    }
    regionStats
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: featureFunction,
                style: style
            })
            map.addLayer(geoJSON)
        })
}

/**
 * Initialises a map.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addStaticPTMap (id) {
    const map = makeMapOnFrance(id)

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

    displayRegions(map, onEachRegionFeature, styleRegion)
    displayAoms(map, onEachAomFeature, style)

    addLegend(map,
        '<h4>Disponibilité des horaires théoriques</h4>',
        ['green', 'orange', 'grey'],
        ['Données disponibles', 'Données partiellement disponibles', 'Aucune donnée disponible']
    )

    return map
}

/**
 * Initialises a map with the realtime covergae.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addRealTimePTMap (id) {
    const map = makeMapOnFrance(id)

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const format = feature.properties.dataset_formats
        const gtfsRT = (format.gtfs_rt !== undefined ? format.gtfs_rt : 0)
        const siri = (format.siri !== undefined ? format.siri : 0)
        const siriLite = (format.siri_lite !== undefined ? format.siri_lite : 0)
        const countOfficial = gtfsRT + siri + siriLite

        let countNonStandardRT = format.non_standard_rt
        if (countOfficial === undefined && countNonStandardRT === 0) {
            return null
        }

        let bind = `<strong>${name}</strong><br/>${type}`
        if (countOfficial) {
            const text = countOfficial === 1 ? 'Un jeu de données standardisé' : `${countOfficial} jeux de données standardisés`
            const commune = feature.properties.id
            bind += `<br/><a href="/datasets/aom/${commune}">${text}</a>`
        }

        if (countNonStandardRT) {
            const text = 'jeu de données non officiellement référencé'
            bind += `<br/><a href="/real_time">${text}</a>`
        }
        layer.bindPopup(bind)
    }

    const styles = {
        stdRT: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.5
        },
        nonStdRT: {
            weight: 1,
            color: 'red',
            fillOpacity: 0.3
        },
        both: {
            weight: 1,
            color: 'orange',
            fillOpacity: 0.5
        }
    }

    const style = feature => {
        const format = feature.properties.dataset_formats
        const hasStdRT = format.gtfs_rt !== undefined ||
            format.siri !== undefined ||
            format.siri_lite !== undefined
        const hasNonStdRT = format.non_standard_rt += 0

        if (hasStdRT && !hasNonStdRT) {
            return styles.stdRT
        }
        if (hasNonStdRT && !hasStdRT) {
            return styles.nonStdRT
        }
        return styles.both
    }

    const filter = feature => {
        const formats = feature.properties.dataset_formats
        return formats.gtfs_rt !== undefined ||
            formats.non_standard_rt !== 0 ||
            formats.siri !== undefined ||
            formats.siri_lite !== undefined
    }

    displayAoms(map, onEachAomFeature, style, filter)

    addLegend(map,
        '<h4>Disponibilité des horaires temps réel</h4>',
        ['green', 'red', 'orange'],
        ['Données disponibles', 'Données disponibles non standard ou non ouvertes', 'Données mixtes']
    )

    return map
}

/**
 * Initialises a map with the realtime covergae.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addPtFormatMap (id) {
    const map = makeMapOnFrance(id)

    const styles = {
        gtfs: {
            weight: 1,
            fillOpacity: 0.5,
            color: 'green'
        },
        netex: {
            weight: 1,
            color: 'red',
            fillOpacity: 0.3
        },
        both: {
            weight: 1,
            color: 'orange',
            fillOpacity: 0.5
        },
        unavailable: {
            weight: 1,
            fillOpacity: 0.0,
            color: 'grey'
        }
    }

    const style = feature => {
        const gtfs = feature.properties.dataset_formats.gtfs
        const hasGTFS = gtfs !== undefined
        const netex = feature.properties.dataset_formats.netex
        const hasNeTex = netex !== undefined

        if (hasGTFS && hasNeTex) {
            return styles.both
        }
        if (hasNeTex) {
            return styles.netex
        }
        if (hasGTFS) {
            return styles.gtfs
        }
    }

    const filter = feature => {
        const formats = feature.properties.dataset_formats
        return formats.gtfs !== undefined || formats.netex !== undefined
    }

    displayAoms(map,
        (feature, layer) => {
            const name = feature.properties.nom
            const commune = feature.properties.id

            const bind = `<a href="/datasets/aom/${commune}">${name}<br/></a>`
            layer.bindPopup(bind)
        },
        style,
        filter
    )

    addLegend(map,
        '<h4>Format de données</h4>',
        ['green', 'red', 'orange'],
        ['GTFS', 'NeTEx', 'GTFS & NeTEx']
    )

    return map
}

/**
 * Initialises a map with the bss covergae.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addBssMap (id) {
    const map = makeMapOnFrance(id)

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const commune = feature.properties.id

        const bind = `<a href="/datasets/aom/${commune}">${name}<br/></a>`
        layer.bindPopup(bind)
    }

    const style = feature => {
        return {
            weight: 1,
            color: 'green',
            fillOpacity: 0.5
        }
    }

    const filter = feature => {
        const types = feature.properties.dataset_types
        return types.bike_sharing !== undefined
    }

    displayAoms(map, onEachAomFeature, style, filter)
    addLegend(map,
        '<h4>Disponibilité des données de vélos en libre service</h4>',
        ['green'],
        ['Données disponibles']
    )

    return map
}

addStaticPTMap('map')

addPtFormatMap('pt_format_map')

addRealTimePTMap('rt_map')

addBssMap('bss_map')
