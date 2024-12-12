const { merge } = require('webpack-merge')
const common = require('./webpack.common.js')
const CssMinimizerPlugin = require('css-minimizer-webpack-plugin')

console.log('webpack production configuration is used 🚀')

const config = {
    mode: 'production',
    optimization: {
        minimizer: [
            // For webpack@5 you can use the `...` syntax to extend existing minimizers (i.e. `terser-webpack-plugin`), uncomment the next line
            '...',
            new CssMinimizerPlugin()
        ]
    }
}

// Enable caching only in the continuous integration env to speed-up builds
if (process.env.CI === 'true') {
    console.log('cache is enabled ♻️⚡️')

    config.cache = {
        type: 'filesystem',
        compression: 'gzip'
    }
}

module.exports = merge(common, config)
