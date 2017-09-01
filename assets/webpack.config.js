const { resolve }       = require('path');
const ExtractTextPlugin = require('extract-text-webpack-plugin');
const extractSass       = new ExtractTextPlugin({ filename: '../css/app.css', allChunks: true });

module.exports = {
    entry: ['./javascripts/app.js', './stylesheets/app.scss'],
    output: {
        path: resolve('../priv/static/js'),
        filename: 'app.js'
    },
    resolve: {
        modules: [
            resolve('./javascripts'),
            resolve('./stylesheets'),
            resolve('elm-stuff'),
            resolve('node_modules')
        ],
        extensions: ['.elm', '.js', '.scss']
    },
    plugins: [extractSass],
    devtool: 'source-map',
    module: {
        noParse: /\.elm$/,
        rules: [{
            test: /\.elm$/,
            exclude: [/elm-stuff/, /node_modules/],
            use: {
                loader: 'elm-webpack-loader',
                options: {
                    cwd: __dirname,
                    debug: false,
                    warn: true
                }
            }
        }, {
            test: /\.js$/,
            exclude: [/elm-stuff/, /node_modules/],
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
        }]
    }
};
