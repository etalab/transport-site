import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Prism from 'prismjs'
import format from 'xml-formatter'

let Hooks = {}
Hooks.SyntaxColoring = {
    updated () {
        // TODO: avoid re-render if the response has not changed. Currently it is always called, generating
        // very slow pages on Safari at least
        var element = this.el.querySelector('code')
        element.textContent = format(element.textContent, {
            indentation: '  ',
            filter: (node) => node.type !== 'Comment',
            collapseContent: true,
            lineSeparator: '\n'
        })
        Prism.highlightElement(element)
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
