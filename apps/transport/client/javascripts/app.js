import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Prism from 'prismjs'

let Hooks = {}
Hooks.SyntaxColoring = {
    updated () {
        Prism.highlightElement(this.el.querySelector('code'))
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
