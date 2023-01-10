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

Hooks.GTFSDiff = {
    mounted () {
        this.handleEvent('store', (obj) => this.store(obj))
        this.handleEvent('clear', (obj) => this.clear(obj))
        this.handleEvent('restore', (obj) => this.restore(obj))
        console.log('gtfs diff mounted')
    },

    store (obj) {
        console.log('stored !')
        localStorage.setItem(obj.key, obj.data)
    },

    restore (obj) {
        const data = sessionStorage.getItem(obj.key)
        this.pushEvent(obj.event, data)
    },

    clear (obj) {
        sessionStorage.removeItem(obj.key)
    }
}

const csrfToken = document.querySelector('meta[name=\'csrf\']').getAttribute('content')
const liveSocket = new LiveSocket('/live', Socket, { hooks: Hooks, params: { _csrf_token: csrfToken } })
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()

// window.liveSocket = liveSocket
