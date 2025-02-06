import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Prism from 'prismjs'
import format from 'xml-formatter'

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

window.addEventListener('phx:backoffice-form-reset', () => {
    document.getElementById('custom_tag').value = ''
})

window.addEventListener('phx:backoffice-form-owner-reset', () => {
    document.getElementById('js-owner-input').value = ''
})

window.addEventListener('phx:gtfs-diff-focus-steps', () => {
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
