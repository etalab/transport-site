import Leaflet from 'leaflet'
import 'leaflet.pattern'
import { Mapbox } from './map-config'

const regionsUrl = '/api/stats/regions'
const aomsUrl = '/api/stats/'
const vehiclesSharingUrl = '/api/stats/vehicles-sharing'
const qualityUrl = '/api/stats/quality'

const lightGreen = '#BCE954'

const makeMapOnView = (id, view) => {
    const map = Leaflet.map(id, {
        attributionControl: view.display_legend,
        zoomControl: view.display_legend
    }).setView(view.center, view.zoom)

    map.createPane('aoms')
    map.getPane('aoms').style.zIndex = 650

    Leaflet.tileLayer(Mapbox.url, {
        accessToken: Mapbox.accessToken,
        attribution: Mapbox.attribution,
        maxZoom: Mapbox.maxZoom,
        tileSize: Mapbox.tileSize,
        zoomOffset: Mapbox.zoomOffset
    }).addTo(map)

    return map
}

// helper function to add legends
const getLegend = (title, colorClasses, labels) => {
    const legend = Leaflet.control({ position: 'bottomright' })
    legend.onAdd = (_map) => {
        const div = Leaflet.DomUtil.create('div', 'info legend')
        div.innerHTML += title
        // loop through our density intervals and generate a label with a colored square for each interval
        for (let i = 0; i < colorClasses.length; i++) {
            div.innerHTML += `<i class="map-bg-${colorClasses[i]}"></i>${labels[i]}<br/>`
        }
        return div
    }

    return legend
}

// simple cache on stats
let aomStats = null
let regionStats = null
let vehiclesSharingStats = null
let qualityStats = null

function getAomsFG (featureFunction, style, filter = null) {
    const aomsFeatureGroup = Leaflet.featureGroup()

    if (aomStats == null) {
        aomStats = fetch(aomsUrl)
            .then(response => { return response.json() })
    }
    aomStats
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: featureFunction,
                style,
                filter,
                pane: 'aoms'
            })
            aomsFeatureGroup.addLayer(geoJSON)
        })
    return aomsFeatureGroup
}

function getRegionsFG (featureFunction, style) {
    const regionsFeatureGroup = Leaflet.featureGroup()
    if (regionStats == null) {
        regionStats = fetch(regionsUrl)
            .then(response => { return response.json() })
    }
    regionStats
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: featureFunction,
                style,
                pointToLayer: (_point, _) => null
            })
            regionsFeatureGroup.addLayer(geoJSON)
        })
    return regionsFeatureGroup
}

function displayVehiclesSharing (map, featureFunction) {
    if (vehiclesSharingStats == null) {
        vehiclesSharingStats = fetch(vehiclesSharingUrl).then(response => {
            return response.json()
        })
    }
    vehiclesSharingStats.then(response => {
        const options = {
            fillColor: '#0066db',
            radius: 5,
            stroke: false,
            fillOpacity: 0.9
        }
        const geoJSON = Leaflet.geoJSON(response, {
            onEachFeature: featureFunction,
            pointToLayer: (_, latlng) => Leaflet.circleMarker(latlng, options)
        })
        map.addLayer(geoJSON)
    })
}

function displayQuality (featureFunction, style) {
    const qualityFeatureGroup = Leaflet.featureGroup()

    if (qualityStats == null) {
        qualityStats = fetch(qualityUrl)
            .then(response => { return response.json() })
    }
    qualityStats
        .then(response => {
            const geoJSON = Leaflet.geoJSON(response, {
                onEachFeature: featureFunction,
                style
            })
            qualityFeatureGroup.addLayer(geoJSON)
        })
    return qualityFeatureGroup
}

/**
 * Initialises a map.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addStaticPTMapRegions (id, view) {
    const map = makeMapOnView(id, view)

    const nbBaseSchedule = (feature) => feature.properties.dataset_types.pt

    function onEachRegionFeature (feature, layer) {
        const name = feature.properties.nom
        const id = feature.properties.id
        const count = nbBaseSchedule(feature)
        const text = count === 0
            ? 'Aucun jeu de données'
            : count === 1
                ? 'Un jeu de données'
                : `${count} jeux de données`
        const popupContent = `<strong>${name}</strong><br/><a href="/datasets/region/${id}?type=public-transit#datasets-results">${text}</a>`
        layer.bindPopup(popupContent)
    }

    const regionStyles = {
        completed: {
            weight: 2,
            color: 'green'
        },
        partial: {
            weight: 1,
            color: lightGreen
        },
        unavailable: {
            weight: 2,
            color: 'grey'
        }
    }

    const styleRegion = feature => {
        if (feature.properties.completed) {
            return regionStyles.completed
        }
        const count = nbBaseSchedule(feature)
        if (count === 0) {
            return regionStyles.unavailable
        } else {
            return regionStyles.partial
        }
    }

    const regionsFG = getRegionsFG(onEachRegionFeature, styleRegion)
    regionsFG.addTo(map)

    if (view.display_legend) {
        getLegend(
            '<h4>Disponibilité des horaires théoriques</h4>',
            ['green', 'light-green', 'grey'],
            ['Données publiées et région partenaire', 'Données publiées', 'Aucune donnée publiée']
        ).addTo(map)
    }
}

function addStaticPTMapAOMS (id, view) {
    const map = makeMapOnView(id, view)

    const nbBaseSchedule = (feature) => feature.properties.dataset_types.pt

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const count = nbBaseSchedule(feature)
        const text = count === 0
            ? 'Aucun jeu de données'
            : count === 1
                ? 'Un jeu de données'
                : `${count} jeux de données`
        const extra = feature.properties.nb_other_datasets > 0
            ? '<br>Des données sont disponibles au sein d\'un jeu agrégé. '
            : ''
        const aomId = feature.properties.id
        layer.bindPopup(`<strong>${name}</strong><br>(${type})<br/>${text} propre à l'AOM. ${extra}<br><a href="/datasets/aom/${aomId}">Voir les jeux de données</a>`)
    }

    const smallStripes = new Leaflet.StripePattern({ angle: -45, color: 'green', spaceColor: lightGreen, spaceOpacity: 1, weight: 1, spaceWeight: 1, height: 2 })
    const bigStripes = new Leaflet.StripePattern({ angle: -45, color: 'green', spaceColor: lightGreen, spaceOpacity: 1, weight: 4, spaceWeight: 4, height: 8 })
    smallStripes.addTo(map)
    bigStripes.addTo(map)

    const styles = {
        unavailable: {
            weight: 1,
            color: 'grey',
            fillOpacity: 0.6
        },
        availableEverywhere: {
            smallStripes: {
                weight: 1,
                color: 'green',
                fillOpacity: 0.6,
                fillPattern: smallStripes
            },
            bigStripes: {
                weight: 1,
                color: 'green',
                fillOpacity: 0.6,
                fillPattern: bigStripes
            }
        },
        available: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.6
        },
        availableElsewhere: {
            weight: 1,
            color: lightGreen,
            fillOpacity: 0.6
        }
    }

    const style = zoom => feature => {
        const count = nbBaseSchedule(feature)
        if (count > 0 && feature.properties.nb_other_datasets > 0) {
            return zoom > 6 ? styles.availableEverywhere.bigStripes : styles.availableEverywhere.smallStripes
        } else if (count > 0) {
            return styles.available
        } else if (feature.properties.nb_other_datasets > 0) {
            return styles.availableElsewhere
        } else {
            return styles.unavailable
        }
    }

    const aomsFG = getAomsFG(onEachAomFeature, style(map.getZoom()))
    aomsFG.addTo(map)
    map.on('zoomend', () => {
        // change stripes width depending on the zoom level
        aomsFG.setStyle(style(map.getZoom()))
    })

    if (view.display_legend) {
        getLegend(
            '<h4>Disponibilité des horaires théoriques :</h4>',
            ['green', 'light-green', 'stripes-green-light-green', 'grey'],
            ['Pour l\'AOM spécifiquement', 'Dans un jeu de données agrégé', 'Pour l\'AOM <strong>et</strong> dans un jeu de données agrégé', 'Aucune donnée disponible']
        ).addTo(map)
    }
}

function addStaticPTUpToDate (id, view) {
    const map = makeMapOnView(id, view)

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const expiredFrom = feature.properties.quality.expired_from
        let text = ''
        if (expiredFrom.status === 'outdated') {
            text = `Les données ne sont plus à jour depuis ${expiredFrom.nb_days} jour`
            if (expiredFrom.nb_days > 1) {
                text += 's'
            }
        } else {
            text = {
                no_data: "Aucune données pour l'AOM",
                unreadable: 'données illisibles',
                up_to_date: 'Les données sont à jour'
            }[expiredFrom.status]
        }
        const id = feature.properties.id
        layer.bindPopup(`<a href="/datasets/aom/${id}">${name}</a><br>(${type})<br/>${text}`)
    }

    const styles = {
        outdated: {
            weight: 1,
            color: 'orange',
            fillOpacity: 0.6
        },
        up_to_date: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.6
        },
        unreadable: {
            weight: 1,
            color: 'red',
            fillOpacity: 0.6
        },
        no_data: {
            weight: 1,
            color: 'grey',
            fillOpacity: 0.6
        }
    }

    const style = feature => {
        return styles[feature.properties.quality.expired_from.status]
    }
    const qualityFG = displayQuality(onEachAomFeature, style)

    qualityFG.addTo(map)

    if (view.display_legend) {
        getLegend(
            '<h4>Fraicheur des données</h4>',
            ['green', 'orange', 'red', 'grey'],
            ['Données à jour', 'Données pas à jour', 'Données illisibles', 'Pas de données']
        ).addTo(map)
    }
}

function addStaticPTQuality (id, view) {
    const map = makeMapOnView(id, view)

    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const errorLevel = feature.properties.quality.error_level
        let text = ''
        if (errorLevel === 'Error') {
            text = 'Les données contiennent des erreurs.'
        } else if (errorLevel === 'Warning') {
            text = 'Les données contiennent des avertissements.'
        } else if (errorLevel === 'Fatal') {
            text = 'Les données ne respectent pas les spécifications.'
        } else if (errorLevel === 'Information' || errorLevel === 'NoError') {
            text = 'Les données sont de bonne qualité.'
        } else {
            text = 'Pas de données valides disponible.'
        }
        const id = feature.properties.id
        layer.bindPopup(`<a href="/datasets/aom/${id}">${name}</a><br>(${type})<br/>${text}`)
    }
    const styles = {
        fatal: {
            weight: 1,
            color: 'red',
            fillOpacity: 0.6
        },
        error: {
            weight: 1,
            color: 'orange',
            fillOpacity: 0.6
        },
        warning: {
            color: lightGreen,
            weight: 1,
            fillOpacity: 0.6
        },
        good: {
            weight: 1,
            color: 'green',
            fillOpacity: 0.6
        },
        unavailable: {
            weight: 1,
            color: 'grey',
            fillOpacity: 0.6
        }
    }

    const style = feature => {
        const quality = feature.properties.quality.error_level
        if (quality === 'Fatal') {
            return styles.fatal
        } else if (quality === 'Error') {
            return styles.error
        } else if (quality === 'Warning') {
            return styles.warning
        } else if (quality === 'Information' || quality === 'NoError') {
            return styles.good
        } else {
            return styles.unavailable
        }
    }
    const qualityFG = displayQuality(onEachAomFeature, style)

    qualityFG.addTo(map)

    if (view.display_legend) {
        getLegend(
            '<h4>Qualité des données courantes</h4>',
            ['red', 'orange', 'light-green', 'green', 'grey'],
            ['Non conforme', 'Erreur', 'Satisfaisante', 'Bonne', 'Pas de données à jour']
        ).addTo(map)
    }
}

/**
 * Initialises a map with the realtime coverage.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addRealTimePTMap (id, view) {
    const map = makeMapOnView(id, view)
    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const format = feature.properties.dataset_formats
        const gtfsRT = (format.gtfs_rt !== undefined ? format.gtfs_rt : 0)
        const siri = (format.siri !== undefined ? format.siri : 0)
        const siriLite = (format.siri_lite !== undefined ? format.siri_lite : 0)
        const countRealTime = gtfsRT + siri + siriLite

        if (countRealTime === undefined) {
            return null
        }

        let bind = `<strong>${name}</strong><br/>${type}`
        if (countRealTime) {
            const text = countRealTime === 1 ? 'Un jeu de données' : `${countRealTime} jeux de données`
            const aomId = feature.properties.id
            bind += `<br/><a href="/datasets/aom/${aomId}">${text}</a>`
        }
        layer.bindPopup(bind)
    }

    const style = feature => {
        const format = feature.properties.dataset_formats
        const hasRealTime = format.gtfs_rt !== undefined ||
            format.siri !== undefined ||
            format.siri_lite !== undefined

        if (hasRealTime) {
            return {
                weight: 1,
                color: 'green',
                fillOpacity: 0.5
            }
        }

        return {
            weight: 1,
            fillOpacity: 0.6,
            color: 'grey'
        }
    }

    const aomsFG = getAomsFG(onEachAomFeature, style)
    aomsFG.addTo(map)

    if (view.display_legend) {
        const legend = getLegend(
            '<h4>Disponibilité des horaires temps réel</h4>',
            ['green', 'grey'],
            [
                'Données disponibles sur transport.data.gouv.fr',
                'Pas de données / Données non standardisées'
            ]
        )
        legend.addTo(map)
    }
}

/**
 * Initialises a map with the realtime format.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addRealTimePtFormatMap (id, view) {
    const map = makeMapOnView(id, view)
    function onEachAomFeature (feature, layer) {
        const name = feature.properties.nom
        const type = feature.properties.forme_juridique
        const format = feature.properties.dataset_formats
        const gtfsRT = format.gtfs_rt ?? 0
        const siri = format.siri ?? 0
        const siriLite = format.siri_lite ?? 0
        const countRealTime = gtfsRT + siri + siriLite

        if (countRealTime === undefined) {
            return null
        }

        let bind = `<div class="pb-6"><strong>${name}</strong><br/>${type}</div>`
        if (countRealTime) {
            const text = countRealTime === 1 ? 'Une ressource' : `${countRealTime} ressources`
            const commune = feature.properties.id
            bind += `<div class="pb-6"><a href="/datasets/aom/${commune}">${text}</a>`
            bind += '<br/>formats :'
            const formats = []
            if (gtfsRT) {
                formats.push('GTFS-RT')
            }
            if (siri) {
                formats.push('SIRI')
            }
            if (siriLite) {
                formats.push('SIRI Lite')
            }
            bind += ` ${formats.join(', ')}</div>`
        }

        layer.bindPopup(bind)
    }
    const smallStripes = new Leaflet.StripePattern({ angle: -45, color: lightGreen, spaceColor: 'blue', spaceOpacity: 1, weight: 1, spaceWeight: 1, height: 2 })
    const bigStripes = new Leaflet.StripePattern({ angle: -45, color: lightGreen, spaceColor: 'blue', spaceOpacity: 1, weight: 4, spaceWeight: 4, height: 8 })
    smallStripes.addTo(map)
    bigStripes.addTo(map)
    const legends = {
        gtfs_rt: { label: 'GTFS-RT', color: 'blue' },
        siri: { label: 'SIRI', color: 'light-green' },
        gtfs_rt_siri: { label: 'GTFS-RT + SIRI', color: 'stripes-green-light-green' },
        siri_lite: { label: 'SIRI Lite', color: 'green' },
        multiple: { label: 'Multiple', color: 'orange' }
    }

    const styles = {
        gtfs_rt: {
            weight: 1,
            fillOpacity: 0.5,
            color: legends.gtfs_rt.color
        },
        siri: {
            weight: 1,
            color: lightGreen,
            fillOpacity: 0.3
        },
        siri_lite: {
            weight: 1,
            color: legends.siri_lite.color,
            fillOpacity: 0.5
        },
        multiple: {
            weight: 1,
            color: legends.multiple.color,
            fillOpacity: 0.5
        },
        gtfs_rt_siri: {
            smallStripes: {
                weight: 1,
                color: 'blue',
                fillOpacity: 0.6,
                fillPattern: smallStripes
            },
            bigStripes: {
                weight: 1,
                color: 'blue',
                fillOpacity: 0.6,
                fillPattern: bigStripes
            }
        },
        unavailable: {
            weight: 1,
            fillOpacity: 0.0,
            color: 'grey'
        }
    }
    const style = zoom => feature => {
        const format = feature.properties.dataset_formats
        const hasGtfsRt = format.gtfs_rt > 0
        const hasSiri = format.siri > 0
        const hasSiriLite = format.siri_lite > 0
        const formatNb = [hasSiri, hasSiriLite, hasGtfsRt].filter(x => !!x).length
        const hasMultipleFormats = formatNb > 1

        if (hasGtfsRt && hasSiri && formatNb === 2) {
            return zoom > 6 ? styles.gtfs_rt_siri.bigStripes : styles.gtfs_rt_siri.smallStripes
        } else if (hasMultipleFormats) {
            return styles.multiple
        } else if (hasGtfsRt) {
            return styles.gtfs_rt
        } else if (hasSiri) {
            return styles.siri
        } else if (hasSiriLite) {
            return styles.siri_lite
        } else {
            return styles.unavailable
        }
    }

    const filter = feature => {
        const formats = feature.properties.dataset_formats
        return formats.gtfs_rt !== undefined ||
            formats.siri !== undefined ||
            formats.siri_lite !== undefined
    }
    const aomsFG = getAomsFG(onEachAomFeature, style(map.getZoom()), filter)
    map.on('zoomend', () => aomsFG.setStyle(style(map.getZoom())))

    aomsFG.addTo(map)

    if (view.display_legend) {
        getLegend(
            '<h4>Format des données temps réel</h4>',
            Object.entries(legends).map(([key, legend]) => legend.color),
            Object.entries(legends).map(([key, legend]) => legend.label)
        ).addTo(map)
    }
}

/**
 * Initialises a map with the realtime coverage.
 * @param  {String} id Dom element id, where the map is to be bound.
 * @param  {String} aomsUrl Url exposing a {FeatureCollection}.
 */
function addPtFormatMap (id, view) {
    const map = makeMapOnView(id, view)

    const styles = {
        gtfs: {
            weight: 1,
            fillOpacity: 0.5,
            color: 'blue'
        },
        netex: {
            weight: 1,
            color: 'green',
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
        const hasNeTEx = netex !== undefined

        if (hasGTFS && hasNeTEx) {
            return styles.both
        }
        if (hasNeTEx) {
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

    const aomsFG = getAomsFG(
        (feature, layer) => {
            const name = feature.properties.nom
            const commune = feature.properties.id

            const bind = `<a href="/datasets/aom/${commune}">${name}<br/></a>`
            layer.bindPopup(bind)
        },
        style,
        filter
    )
    aomsFG.addTo(map)

    if (view.display_legend) {
        const legend = getLegend(
            '<h4>Format de données</h4>',
            ['blue', 'green', 'orange'],
            ['GTFS', 'NeTEx', 'GTFS & NeTEx']
        )
        legend.addTo(map)
    }
}

function addVehiclesSharingMap (id, view) {
    const map = makeMapOnView(id, view)

    displayVehiclesSharing(map, (feature, layer) => {
        const names = feature.properties.names
        const slugs = feature.properties.slugs
        const bind = names.map((name, i) => `<a href="/datasets/${slugs[i]}" target="_blank">${name}<br/></a>`).join('')
        layer.bindPopup(bind)
    })
}

const droms = {
    antilles: {
        center: [15.372, -61.3367],
        zoom: 7
    },
    guyane: {
        center: [3.830, -53.097],
        zoom: 6
    },
    nouvelle_caledonie: {
        center: [-22, 166],
        zoom: 6
    },
    metropole: {
        center: [44.670, 2.087],
        zoom: 5,
        display_legend: true
    },
    reunion: {
        center: [-21.0883, 55.5155],
        zoom: 8
    }
}

for (const [drom, view] of Object.entries(droms)) {
    addStaticPTMapRegions(`map_regions_${drom}`, view)
    addStaticPTUpToDate(`pt_up_to_date_${drom}`, view)
    addStaticPTMapAOMS(`map_aoms_${drom}`, view)
    addStaticPTQuality(`pt_quality_${drom}`, view)
    addPtFormatMap(`pt_format_map_${drom}`, view)
    addRealTimePTMap(`rt_map_${drom}`, view)
    addRealTimePtFormatMap(`rt_pt_format_map_${drom}`, view)
    addVehiclesSharingMap(`vehicles_map_${drom}`, view)
}
