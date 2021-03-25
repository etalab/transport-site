const { merge } = require('webpack-merge')
const common = require('./webpack.common.js')

console.log('webpack dev configuration is used')

module.exports = merge(common, {
    mode: 'development',
    devtool: 'source-map'
})
