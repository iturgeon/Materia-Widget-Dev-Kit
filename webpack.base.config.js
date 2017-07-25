const path              = require('path')
const webpack           = require('webpack')
const CleanPlugin       = require('clean-webpack-plugin')
const CopyPlugin        = require('copy-webpack-plugin')
const ExtractTextPlugin = require('extract-text-webpack-plugin')
const ZipPlugin         = require('zip-webpack-plugin')

// Default Materia Widget Config
const defaultCfg = {
	cleanName: '',
	srcPath: path.join(process.cwd(), 'src'),
	outputPath: path.join(process.cwd(), 'build'),
	demoPath: 'demo.json',
	installPath: 'install.yaml',
	iconsPath: '_icons',
	scorePath: '_score/',
	screenshotsPath: '_screen-shots/',
	assetsPath: 'assets/',
	preCopy: []
}

// creators and players may reference materia core files directly
// To do so rather than hard-coding the actual location of those files
//the build process will replace those references with the current relative paths to those files
const materiaJSReplacements = [
	{ search: /src=(\\?("|')?)materia.enginecore.js(\\?("|')?)/g,      replace: 'src=\\"../../../js/materia.enginecore.js\\"' },
	{ search: /src=(\\?("|')?)materia.score.js(\\?("|')?)/g,           replace: 'src=\\"../../../js/materia.score.js\\"' },
	{ search: /src=(\\?("|')?)materia.creatorcore.js(\\?("|')?)/g,     replace: 'src=\\"../../../js/materia.creatorcore.js\\"' },
	{ search: /src=(\\?("|')?)materia.storage.manager.js(\\?("|')?)/g, replace: 'src=\\"../../../js/materia.storage.manager.js\\"' },
	{ search: /src=(\\?("|')?)materia.storage.table.js(\\?("|')?)/g,   replace: 'src=\\"../../../js/materia.storage.table.js\\"' }
];

// Load the materia configuration settings from the package.json file
const configFromPackage = () => {
	let packagePath  = path.join(process.cwd(), 'package.json')
	let packageJson  = require(packagePath)

	return {
		cleanName : packageJson.materia.cleanName.toLowerCase(),
	}
}


// This is a base config for building legacy widgets
// It will skip webpack's javascript functionality
// to avoid having to make changes to the source code of those widgets
// the config argument allows you to override some settings
const getLegacyWidgetBuildConfig = (config = {}) => {
	// load and combine the config
	let materiaConfig = configFromPackage()
	cfg = Object.assign({}, defaultCfg, {cleanName:materiaConfig.cleanName}, config)
	// set up source and destination paths
	let srcPath = cfg.srcPath + path.sep
	let outputPath = cfg.outputPath + path.sep

	// return a webpack config you can update
	return {
		target: 'node',
		entry: {
			'creator.js': [
				path.join(srcPath, 'creator.coffee')
			],
			'player.js': [
				path.join(srcPath, 'player.coffee')
			],
			'creator.css': [
				path.join(srcPath, 'creator.html'),
				path.join(srcPath, 'creator.scss')
			],
			'player.css': [
				path.join(srcPath, 'player.html'),
				path.join(srcPath, 'player.scss')
			]
		},

		output: {
			path: outputPath,
			filename: '[name]',
			publicPath: ''
		},

		module: {
			rules: [
				{
					test: /\.coffee$/,
					exclude: /node_modules/,
					loader: ExtractTextPlugin.extract({
						use: ['raw-loader', 'coffee-loader']
					})
				},
				{
					test: /\.(jpe?g|png|gif|svg)$/i,
					loader: 'file-loader',
					query: {
						emitFile: false,
						publicPath: 'assets/img/',
						name: '[name].[ext]'
					}
				},
				{
					test: /\.html$/,
					exclude: /node_modules/,
					use: [
						{
							loader: 'file-loader',
							options: { name: '[name].html' }
						},
						{
							loader: 'extract-loader',
							query: 'publicPath=/'
						},
						{
							loader: 'string-replace-loader',
							options: { multiple: materiaJSReplacements }
						},
						'html-loader'
					]
				},
				{
					// Process SASS/SCSS Files
					test: /\.s[ac]ss$/,
					exclude: /node_modules/,
					loader: ExtractTextPlugin.extract({
						use: [
							'raw-loader',
							{
								// postcss-loader is needed to run autoprefixer
								loader: 'postcss-loader',
								options: {
									plugins: [require('autoprefixer')],
									// if you don't tell postcss where to get it's config, it'll search and die
									// adding this keeps us from having to add a postcss.config.js to each widget
									// override if you need to
									config: { path: `${__dirname}/postcss.config.js`}
								}
							},
							'sass-loader'
						]
					})
				}
			]
		},
		plugins: [
			// clear the build directory
			new CleanPlugin(['build']),

			// copy all the common resources to the build directory
			new CopyPlugin([
				{
					flatten: true,
					from: `${srcPath}${cfg.demoPath}`,
					to: outputPath,
				},
				{
					flatten: true,
					from: `${srcPath}${cfg.installPath}`,
					to: outputPath,
				},
				{
					from: `${srcPath}${cfg.iconsPath}`,
					to: `${outputPath}img`,
					toType: 'dir'
				},
				{
					flatten: true,
					from: `${srcPath}${cfg.scorePath}`,
					to: `${outputPath}_score-modules`,
					toType: 'dir'
				},
				{
					from: `${srcPath}${cfg.screenshotsPath}`,
					to: `${outputPath}img/screen-shots`,
					toType: 'dir'
				},
				{
					from: `${srcPath}${cfg.assetsPath}`,
					to: `${outputPath}assets`,
					toType: 'dir'
				}
			]),

			// extract css from the webpack output
			new ExtractTextPlugin({filename: '[name]'}),

			// zip everything in the build path to zip dir
			new ZipPlugin({
				path: `${outputPath}_output`,
				filename: cfg.cleanName,
				extension: 'wigt'
			})
		]
	};
}

module.exports = {
	materiaJSReplacements: materiaJSReplacements,
	configFromPackage: configFromPackage,
	getLegacyWidgetBuildConfig: getLegacyWidgetBuildConfig,
}
