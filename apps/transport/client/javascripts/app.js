import { Socket } from 'phoenix'
import LiveSocket from 'phoenix_live_view'

const csrfToken = document.querySelector('meta[name=\'csrf-token\']').getAttribute('content')
const liveSocket = new LiveSocket('/live', Socket, { params: { _csrf_token: csrfToken } })
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()

// window.liveSocket = liveSocket
