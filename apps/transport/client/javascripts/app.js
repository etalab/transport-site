import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Prism from 'prismjs'
import format from 'xml-formatter'
import IRVEMap from './irve_map'

const Hooks = {}
Hooks.SyntaxColoring = {
    mounted () {
        this.updated()
    },
    updated () {
        const element = this.el
        const target = document.getElementById(element.dataset.code)
        try {
            target.textContent = format(element.value, {
                indentation: '  ',
                filter: (node) => node.type !== 'Comment',
                collapseContent: true,
                lineSeparator: '\n'
            })
        } catch (_) {
            /* in some cases, the returned content is not XML, in which case the
               attempt to format fails. We use a catch-all exception to make sure
               we still display the response properly */
            target.textContent = element.value
        }
        Prism.highlightElement(target)
    }
}
Hooks.TextareaAutoexpand = {
    mounted () {
        this.el.addEventListener('input', event => {
            event.target.parentNode.dataset.replicatedValue = event.target.value
        })
    }
}

Hooks.Geolocate = {
    mounted () {
        this.el.addEventListener('click', () => {
            if (!navigator.geolocation) {
                window.alert('Géolocalisation non disponible dans ce navigateur.')
                return
            }
            this.el.disabled = true
            navigator.geolocation.getCurrentPosition(
                pos => {
                    this.el.disabled = false
                    this.pushEvent('locate-here', {
                        lat: pos.coords.latitude.toFixed(6),
                        lon: pos.coords.longitude.toFixed(6)
                    })
                },
                err => {
                    this.el.disabled = false
                    window.alert('Géolocalisation refusée ou indisponible : ' + err.message)
                },
                { enableHighAccuracy: true, timeout: 10000 }
            )
        })
    }
}

Hooks.IRVEMap = IRVEMap

Hooks.IRVEBlink = {
    mounted () {
        this.handleEvent('irve:blink', ({ cells }) => {
            cells.forEach(({ id, field }) => {
                const td = this.el.querySelector(
                    `td[data-cell-id="${CSS.escape(id)}"][data-cell-field="${CSS.escape(field)}"]`
                )
                if (!td) return
                td.classList.remove('irve-blink')
                // force reflow so the animation restarts even on consecutive ticks
                void td.offsetWidth
                td.classList.add('irve-blink')
            })
        })
    }
}

window.addEventListener('phx:backoffice-form-reset', () => {
    document.getElementById('custom_tag').value = ''
})

window.addEventListener('phx:backoffice-form-owner-reset', () => {
    document.getElementById('js-owner-input').value = ''
})

window.addEventListener('phx:backoffice-form-spatial-areas-reset', () => {
    document.getElementById('spatial_areas_search_input').value = ''
})

window.addEventListener('phx:backoffice-form-offer-reset', () => {
    document.getElementById('js-offer-input').value = ''
})

window.addEventListener('phx:backoffice-form-dataset-subtypes-reset', () => {
    document.getElementById('js-dataset-subtype-input').value = ''
})

window.addEventListener('phx:gtfs-diff:scroll-to-steps', () => {
    document.getElementById('gtfs-diff-steps').parentElement.scrollIntoView({ behavior: 'smooth' })
})

const csrfToken = document.querySelector('meta[name=\'csrf\']').getAttribute('content')
const liveSocket = new LiveSocket('/live', Socket, { hooks: Hooks, params: { _csrf_token: csrfToken } })
liveSocket.connect()

// Track analytics events for DOM elements by a `data-tracking-category`.
// The event will be recorded on a click event
// See https://matomo.org/faq/reports/implement-event-tracking-with-matomo/#how-to-set-up-matomo-event-tracking-with-javascript
document.querySelectorAll('[data-tracking-category]').forEach(el => {
    el.addEventListener('click', function (event) {
        const target = event.target
        const name = target.dataset.trackingName || ''
        window._paq.push(['trackEvent', target.dataset.trackingCategory, target.dataset.trackingAction, name])
    })
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()

// window.liveSocket = liveSocket
