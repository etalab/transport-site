import { Socket } from 'phoenix'
import LiveSocket from 'phoenix_live_view'

const liveSocket = new LiveSocket('/live', Socket)
liveSocket.connect()
