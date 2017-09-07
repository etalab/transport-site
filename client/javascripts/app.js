const Elm        = require('./Transport')
const { addMap } = require('./leaflet')

const init = async function () {
    Elm.Transport.embed(document.getElementById('main'))
    return new Promise(resolve => setTimeout(resolve, 500))
}

init().then(() => {
    addMap('map', '/data/home.geojson')
})
