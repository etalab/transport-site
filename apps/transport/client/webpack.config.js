const { resolve } = require('path')
const devMode = process.env.NODE_ENV !== 'production'
const webpack = require('webpack')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const extractImages = new CopyWebpackPlugin([{ from: 'images', to: '../images' }])
const extractSass = new MiniCssExtractPlugin({ filename: '../css/app.css', allChunks: true })
const fetchPolyfill = new webpack.ProvidePlugin({ fetch: 'exports-loader?self.fetch!whatwg-fetch/dist/fetch.umd' })
const promisePolyfill = new webpack.ProvidePlugin({ Promise: 'core-js/es/promise' })
const processEnv = new webpack.DefinePlugin({ 'process.env': { DATAGOUVFR_SITE: JSON.stringify(process.env.DATAGOUVFR_SITE) } })

module.exports = {
    mode: devMode ? 'development' : 'production',
    entry: {
        app: './javascripts/app.js',
        map: './javascripts/map.js',
        mapcsv: './javascripts/map-csv.js',
        mapgeojson: './javascripts/map-geojson.js',
        datasetmap: './javascripts/dataset-map.js',
        utils: './javascripts/utils.js',
        autocomplete: './javascripts/autocomplete.js',
        scss: './stylesheets/app.scss'
    },
    output: {
        path: resolve('../priv/static/js'),
        filename: '[name].js'
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
                test: /\.js$/,
                exclude: [/node_modules/],
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['@babel/preset-env']
                    }
                }
            }, {
                test: /\.scss$/,
                exclude: [/node_modules/],
                use:
                    [
                        MiniCssExtractPlugin.loader,
                        {
                            loader: 'css-loader',
                            options: {
                                sourceMap: true
                            }
                        }, {
                            loader: 'sass-loader',
                            options: {
                                sourceMap: true
                            }
                        }
                    ]
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
