const { merge } = require('webpack-merge')
const common = require('./webpack.common.js')
const CssMinimizerPlugin = require('css-minimizer-webpack-plugin')

console.log('webpack production configuration is used 🚀')

module.exports = merge(common, {
    mode: 'production',
    cache: {
        type: 'filesystem',
        compression: 'gzip'
    },
    optimization: {
        minimizer: [
            // For webpack@5 you can use the `...` syntax to extend existing minimizers (i.e. `terser-webpack-plugin`), uncomment the next line
            '...',
            new CssMinimizerPlugin()
        ]
    }
})
