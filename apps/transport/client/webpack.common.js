const { resolve } = require('path')
const webpack = require('webpack')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const extractImages = new CopyWebpackPlugin({ patterns: [{ from: 'images', to: '../images' }] })
const extractSass = new MiniCssExtractPlugin({ filename: '../css/app.css' })
const promisePolyfill = new webpack.ProvidePlugin({ Promise: 'core-js/es/promise' })

module.exports = {
    entry: {
        app: './javascripts/app.js',
        clipboard: './javascripts/clipboard.js',
        map: './javascripts/map.js',
        resourceviz: './javascripts/resource-viz.js',
        explore: './javascripts/explore.js',
        mapgeojson: './javascripts/map-geojson.js',
        datasetmap: './javascripts/dataset-map.js',
        validationmap: './javascripts/validation-map.js',
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
            'images/layers.png$': resolve('./node_modules/leaflet/dist/images/layers.png'),
            'images/layers-2x.png$': resolve('./node_modules/leaflet/dist/images/layers-2x.png'),
            'images/marker-icon.png$': resolve('./node_modules/leaflet/dist/images/marker-icon.png'),
            'images/marker-icon-2x.png$': resolve('./node_modules/leaflet/dist/images/marker-icon-2x.png'),
            'images/marker-shadow.png$': resolve('./node_modules/leaflet/dist/images/marker-shadow.png')
        }
    },
    plugins: [
        extractImages,
        extractSass,
        promisePolyfill
    ],
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
                type: 'asset/resource',
                generator: {
                    filename: '[name][ext]'
                }
            }, {
                test: /\.(eot|ttf|otf|woff|woff2)(\?v=\d+\.\d+\.\d+)?$/,
                type: 'asset/resource',
                generator: {
                    filename: '[name][ext]'
                }
            }]
    }
}
