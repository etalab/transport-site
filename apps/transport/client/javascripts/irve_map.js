import Leaflet from 'leaflet'
import { LeafletLayer } from 'deck.gl-leaflet'
import { ScatterplotLayer } from '@deck.gl/layers'
import { MapView } from '@deck.gl/core'
import { IGN } from './map-config'

const COLORS = {
    en_service: [76, 175, 80, 220],
    occupe: [255, 152, 0, 220],
    hors_service: [244, 67, 54, 220],
    inconnu: [158, 158, 158, 220],
    no_dynamic: [33, 150, 243, 0]
}

const RING_COLORS = {
    en_service: [56, 142, 60, 255],
    occupe: [230, 81, 0, 255],
    hors_service: [183, 28, 28, 255],
    inconnu: [97, 97, 97, 255],
    no_dynamic: [33, 150, 243, 255]
}

const FLASH_DURATION_MS = 1500
const MOVE_DEBOUNCE_MS = 250

export default {
    mounted () {
        this.map = Leaflet.map(this.el, { renderer: Leaflet.canvas() }).setView([46.5, 2], 5)
        Leaflet.tileLayer(IGN.url, IGN.config).addTo(this.map)

        this.markers = []
        this.flashes = new Map()
        this.suppressMoveend = false
        this.lastSentBboxStr = null

        this.deckLayer = new LeafletLayer({
            views: [new MapView({ repeat: true })],
            layers: [],
            getTooltip: ({ object }) => object && {
                html: `<strong>${escapeHtml(object.nom_station || object.id)}</strong><br>` +
                    `id_pdc_itinerance: <code>${escapeHtml(object.id)}</code><br>` +
                    `état: <strong>${escapeHtml(object.etat)}</strong>` +
                    (object.nom_amenageur ? `<br>aménageur: ${escapeHtml(object.nom_amenageur)}` : '') +
                    (object.nom_operateur ? `<br>opérateur: ${escapeHtml(object.nom_operateur)}` : '') +
                    (object.organization ? `<br>publié par: ${escapeHtml(object.organization)}` : '') +
                    (object.group_size > 1 ? `<br><em>${object.group_size} points au même endroit (sunflower spread)</em>` : '')
            }
        })
        this.map.addLayer(this.deckLayer)

        this.handleEvent('irve:map:markers', ({ markers, bbox, fit }) => {
            this.markers = markers
            if (fit && bbox) {
                this.fitToBbox(bbox)
            }
            this.refreshLayers()
        })

        this.handleEvent('irve:map:flash', ({ ids }) => {
            const expiresAt = performance.now() + FLASH_DURATION_MS
            ids.forEach(id => this.flashes.set(id, expiresAt))
            this.refreshLayers()
            if (!this.flashRaf) this.flashRaf = requestAnimationFrame(this.tickFlashes.bind(this))
        })

        this.map.on('moveend', () => {
            if (this.suppressMoveend) return
            clearTimeout(this.moveTimer)
            this.moveTimer = setTimeout(() => this.emitViewport(), MOVE_DEBOUNCE_MS)
        })

        // Force a resize once Leaflet sees its container size (LiveView mount race).
        setTimeout(() => this.map.invalidateSize(), 50)
    },

    destroyed () {
        if (this.flashRaf) cancelAnimationFrame(this.flashRaf)
        clearTimeout(this.moveTimer)
        if (this.map) this.map.remove()
    },

    emitViewport () {
        const b = this.map.getBounds()
        const bboxStr = [b.getSouth(), b.getWest(), b.getNorth(), b.getEast()]
            .map(n => n.toFixed(6))
            .join(',')
        if (bboxStr === this.lastSentBboxStr) return
        this.lastSentBboxStr = bboxStr
        this.pushEvent('viewport-changed', { bbox: bboxStr })
    },

    fitToBbox ([minLat, minLon, maxLat, maxLon]) {
        this.suppressMoveend = true
        this.map.fitBounds([[minLat, minLon], [maxLat, maxLon]])
        // Mark the bbox we settled on so we don't re-emit it.
        this.lastSentBboxStr = [minLat, minLon, maxLat, maxLon].map(n => Number(n).toFixed(6)).join(',')
        // Release the suppression after Leaflet has finished its move.
        setTimeout(() => { this.suppressMoveend = false }, MOVE_DEBOUNCE_MS + 100)
    },

    tickFlashes () {
        const now = performance.now()
        let any = false
        for (const [id, exp] of this.flashes) {
            if (exp <= now) this.flashes.delete(id); else any = true
        }
        this.refreshLayers()
        this.flashRaf = any ? requestAnimationFrame(this.tickFlashes.bind(this)) : null
    },

    refreshLayers () {
        const data = this.markers
        const baseLayer = new ScatterplotLayer({
            id: 'irve-base',
            data,
            pickable: true,
            stroked: true,
            filled: true,
            radiusMinPixels: 5,
            radiusMaxPixels: 14,
            lineWidthMinPixels: 1.5,
            getPosition: d => [d.lon, d.lat],
            getFillColor: d => COLORS[d.etat] || COLORS.inconnu,
            getLineColor: d => RING_COLORS[d.etat] || RING_COLORS.inconnu,
            getRadius: 8
        })

        const flashing = data.filter(d => this.flashes.has(d.id))
        const halo = new ScatterplotLayer({
            id: 'irve-halo',
            data: flashing,
            stroked: true,
            filled: false,
            lineWidthMinPixels: 3,
            radiusMinPixels: 14,
            radiusMaxPixels: 28,
            getPosition: d => [d.lon, d.lat],
            getLineColor: [255, 235, 59, 220],
            getRadius: 18
        })

        this.deckLayer.setProps({ layers: [baseLayer, halo] })
    }
}

function escapeHtml (s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}
