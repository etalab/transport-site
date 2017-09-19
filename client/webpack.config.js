const { resolve }       = require('path')
const ExtractTextPlugin = require('extract-text-webpack-plugin')
const extractSass       = new ExtractTextPlugin({ filename: '../css/app.css', allChunks: true })

module.exports = {
    entry: ['./javascripts/app.js', './stylesheets/app.scss'],
    output: {
        path: resolve('../priv/static/js'),
        filename: 'app.js'
    },
    resolve: {
        modules: [
            resolve('./node_modules'),
            resolve('./javascripts'),
            resolve('./stylesheets'),
            resolve('./images')
        ],
        // https://github.com/Leaflet/Leaflet/issues/4849#issuecomment-307436996
        alias: {
            './images/layers.png$': resolve('./node_modules/leaflet/dist/images/layers.png'),
            './images/layers-2x.png$': resolve('./node_modules/leaflet/dist/images/layers-2x.png'),
            './images/marker-icon.png$': resolve('./node_modules/leaflet/dist/images/marker-icon.png'),
            './images/marker-icon-2x.png$': resolve('./node_modules/leaflet/dist/images/marker-icon-2x.png'),
            './images/marker-shadow.png$': resolve('./node_modules/leaflet/dist/images/marker-shadow.png')
        },
        extensions: ['.js', '.scss', '.jpg', '.jpeg', '.png', '.gif', '.svg']
    },
    plugins: [extractSass],
    devtool: 'source-map',
    module: {
        rules: [{
            test: /\.js$/,
            exclude: [/node_modules/],
            use: {
                loader: 'babel-loader',
                options: {
                    presets: ['es2017']
                }
            }
        }, {
            test: /\.scss$/,
            use: extractSass.extract({
                use: [{
                    loader: 'css-loader',
                    options: {
                        sourceMap: true
                    }
                }, {
                    loader: 'sass-loader',
                    options: {
                        sourceMap: true
                    }
                }]
            })
        }, {
            test: /\.(js|scss)$/,
            enforce: 'pre',
            loader: 'import-glob-loader'
        }, {
            test: /\.(jpe?g|png|gif|svg)$/,
            use: [
                'url-loader?limit=10000',
                'img-loader'
            ]
        }]
    }
}
