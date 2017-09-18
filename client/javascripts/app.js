import { addMap } from './leaflet'
import riot from 'riot'
import './components/**/*'

riot.mount('*')
addMap('map', '/data/home.geojson')
