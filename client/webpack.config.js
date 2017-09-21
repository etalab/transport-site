const { resolve }       = require('path')
const ExtractTextPlugin = require('extract-text-webpack-plugin')
const extractSass       = new ExtractTextPlugin({ filename: '../css/app.css', allChunks: true })

module.exports = {
    entry: [
        './javascripts/app.js',
        './stylesheets/app.scss'
    ],
    output: {
        path: resolve('../priv/static/js'),
        filename: 'app.js'
    },
    resolve: {
        modules: [resolve('./node_modules')],
        // https://github.com/Leaflet/Leaflet/issues/4849#issuecomment-307436996
        alias: {
            './images/layers.png$': resolve('./node_modules/leaflet/dist/images/layers.png'),
            './images/layers-2x.png$': resolve('./node_modules/leaflet/dist/images/layers-2x.png'),
            './images/marker-icon.png$': resolve('./node_modules/leaflet/dist/images/marker-icon.png'),
            './images/marker-icon-2x.png$': resolve('./node_modules/leaflet/dist/images/marker-icon-2x.png'),
            './images/marker-shadow.png$': resolve('./node_modules/leaflet/dist/images/marker-shadow.png')
        },
        extensions: ['.js', '.scss']
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
            exclude: [/node_modules/],
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
            exclude: [/node_modules/],
            enforce: 'pre',
            loader: 'import-glob-loader'
        }, {
            test: /\.(jpe?g|png|gif|svg)$/,
            exclude: [/font-awesome/],
            use: [{
                loader: 'file-loader',
                options: {
                    name: '[name].[ext]',
                    outputPath: '../images/'
                }
            }]
        }, {
            test: /\.(eot|ttf|woff|woff2|svg)(\?v=\d+\.\d+\.\d+)?$/,
            use: [{
                loader: 'file-loader',
                options: {
                    name: '[name].[ext]',
                    outputPath: '../fonts/'
                }
            }]
        }]
    }
}
