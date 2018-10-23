const { resolve } = require('path')
const webpack = require('webpack')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const ExtractTextPlugin = require('extract-text-webpack-plugin')
const extractImages = new CopyWebpackPlugin([{ from: 'images', to: '../images' }])
const extractSass = new ExtractTextPlugin({ filename: '../css/app.css', allChunks: true })
const fetchPolyfill = new webpack.ProvidePlugin({ fetch: 'imports-loader?this=>global!exports-loader?global.fetch!whatwg-fetch' })
const promisePolyfill = new webpack.ProvidePlugin({ Promise: 'core-js/es6/promise' })
const processEnv = new webpack.DefinePlugin({ 'process.env': { 'DATAGOUVFR_SITE': JSON.stringify(process.env.DATAGOUVFR_SITE) } })

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
        }
    },
    plugins: [
        extractImages,
        extractSass,
        fetchPolyfill,
        promisePolyfill,
        processEnv
    ],
    devtool: 'source-map',
    module: {
        rules: [{ test: /\.css$/, use: ['style-loader', 'css-loader'] },
            {
                test: /\.(js|scss)$/,
                exclude: [/node_modules/],
                enforce: 'pre',
                loader: 'import-glob-loader'
            }, {
                test: /\.tag$/,
                exclude: /node_modules/,
                enforce: 'pre',
                loader: 'riot-tag-loader',
                query: {
                    type: 'es6'
                }
            }, {
                test: /\.tag$/,
                exclude: [/node_modules/],
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['es2015-riot']
                    }
                }
            }, {
                test: /\.js$/,
                exclude: [/node_modules/],
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['es2015']
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
                            sourceMap: true,
                            outputStyle: 'compact'
                        }
                    }]
                })
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
                test: /\.(eot|ttf|otf|woff|woff2|svg)(\?v=\d+\.\d+\.\d+)?$/,
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
