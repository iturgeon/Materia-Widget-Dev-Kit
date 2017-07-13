bodyParser           = require 'body-parser'
exec                 = require('child_process').exec
execSync             = require('child_process').execSync
express              = require 'express'
fs                   = require 'fs'
http                 = require 'http'
path                 = require 'path'
querystring          = require 'querystring'
webpack              = require 'webpack'
webpackHotMiddleware = require 'webpack-hot-middleware'
webpackMiddleware    = require 'webpack-dev-middleware'
yaml                 = require 'yamljs'

config = require path.resolve('webpack.dev.config.js')

app  = express()
# default port number - possibly overridden by command line arguments
port = 8118

# if a valid port number was passed as a command line argument, use it instead of the default
if Number.isInteger +process.argv[2]
	port = +process.argv[2]

# format the output of webpack builds in the terminal
buildOutput =
	colors: true,
	hash: false,
	timings: true,
	chunks: false,
	chunkModules: false,
	modules: false

compiler   = webpack config
middleware = webpackMiddleware compiler,
	publicPath: config.output.publicPath,
	contentBase: 'build',
	stats: buildOutput

# allow iframes to talk to their parent containers
app.use (req, res, next) ->
	res.header 'Access-Control-Allow-Origin', '*'
	res.header 'Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept'
	next()

app.use bodyParser.json()
app.use bodyParser.urlencoded
	extended: true
app.use middleware
app.use webpackHotMiddleware(compiler)

qsets = path.join __dirname, '..', 'qsets'

# start the server
app.listen port, 'localhost', (err) ->
	if err
		console.log err

	install = fs.readFileSync path.join(config.output.publicPath, 'install.yaml')
	title = yaml.parse(install.toString()).general.name

	console.info('==> %s is now running on port %s. Open up http://localhost:%s/ in your browser.', title, port, port);

app.get '/', (req, res) ->
	file = getFile 'index.html'
	res.write templateSwap(file, 'title', getWidgetTitle())
	res.end()

app.get '/media/:id', (req, res) ->
	res.redirect 'http://lorempixel.com/800/600/?c=' + req.params.id

app.post '/saved_qsets', (req, res) ->
	saved_qsets = {}

	files = fs.readdirSync qsets
	for i, file of files
		continue unless file.includes('instance')
		actual_path = path.join qsets, file
		qset_data = JSON.parse(fs.readFileSync(actual_path).toString())[0]
		saved_qsets[qset_data.id] = qset_data.name

	res.write JSON.stringify(saved_qsets)
	res.end()

app.get '/download', (req, res) ->
	productionConfig = require(path.resolve('webpack.package.config.js'))(req.query)

	productionCompiler = webpack productionConfig
	productionMiddleware = webpackMiddleware productionCompiler,
		publicPath: productionConfig.output.publicPath,
		contentBase: 'build'
		stats: buildOutput

	productionMiddleware.waitUntilValid ->
		widget = makeWidget()

		res.set 'Content-Disposition', 'attachment; filename=' + widget.clean_name + '.wigt'
		res.send productionMiddleware.fileSystem.readFileSync path.join(productionConfig.output.path, '_output', widget.clean_name + '.wigt')

app.get '/install', (req, res) ->
	# determine the directory that Materia's files are running from
	targetImage = execSync 'docker ps --filter "name=phpfpm" --format "{{.Names}}"'

	dockerInfo = execSync 'docker inspect ' + targetImage.toString()
	dockerInfo = JSON.parse dockerInfo.toString()

	materiaPath = false

	for k, mount of dockerInfo[0].Mounts
		if mount.Destination is '/var/www/html'
			materiaPath = mount.Source
			break

	productionConfig = require(path.resolve('webpack.package.config.js'))(req.query)

	productionCompiler = webpack productionConfig
	productionMiddleware = webpackMiddleware productionCompiler,
		publicPath: productionConfig.output.publicPath,
		contentBase: 'build'
		stats: buildOutput

	productionMiddleware.waitUntilValid ->
		widget = makeWidget()

		execSync "find " + materiaPath + "/fuel/app/tmp/widget_packages -name '" + widget.clean_name + "*.wigt' -delete"

		file = productionMiddleware.fileSystem.readFileSync path.join(productionConfig.output.path, '_output', widget.clean_name + '.wigt')
		time = new Date().getTime()
		filename = widget.clean_name+'-'+time+'.wigt'

		fs.writeFileSync path.join(materiaPath, '/fuel/app/tmp/widget_packages', filename), file

		installCommand = "cd " + materiaPath +
			" && cd .. " +
			" && ./install_widget.sh " + filename

		installResult = execSync installCommand
		installResult = installResult.toString()

		console.log installResult

		match = installResult.match(/Widget installed\:\ ([A-Za-z0-9\-]+)/)

		if match? and match[1]
			redirectUrl = 'http://127.0.0.1/widgets/'+match[1]
			res.redirect redirectUrl

app.get '/player/:instance?', (req, res) ->
	instance = req.params.instance or 'demo'

	file = getFile 'player_container.html'

	res.write templateSwap(file, 'instance', instance)
	res.end()

app.get '/creator/:instance?', (req, res) ->
	instance = req.params.instance or null

	file = getFile 'creator_container.html'
	file = templateSwap(file, 'instance', instance)

	res.write templateSwap(file, 'port', port)
	res.end()

app.post '/widget_instances_get', (req, res) ->
	id = JSON.parse(req.body.data)[0][0]
	instance = makeWidgetInstance id

	res.send JSON.stringify(instance)

app.post '/widget_instance_save', (req, res) ->
	data = JSON.parse(req.body.data)

	# sweep through the qset items and make sure there aren't any nonstandard question properties
	standard_props = [
		'materiaType',
		'id',
		'type',
		'created_at',
		'questions',
		'answers',
		'options',
		'assets',
	]
	nonstandard_props = []
	for index, item of data[2].data.items
		for prop of item
			console.log prop
			unless prop in standard_props
				nonstandard_props.push '"'+prop+'"'
				delete data[2].data.items[index][prop]
				console.log 'Nonstandard property found in qset: ' + prop

	id = data[0] || new Date().getTime()
	fs.writeFileSync path.join(qsets, id + '.json'), JSON.stringify(data[2])

	instance = makeWidgetInstance(data[0])[0]
	instance.id = id
	instance.name = data[1]
	fs.writeFileSync path.join(qsets, id + '.instance.json'), JSON.stringify([instance])

	# send a warning back to the creator if any nonstandard question properties were detected
	if nonstandard_props.length > 0
		plurals = if nonstandard_props.length > 1 then ['properties', 'were'] else ['property', 'was']
		instance.warning = 'Warning: Nonstandard qset item ' +
			plurals[0] + ' ' + nonstandard_props.join(', ') + ' ' +
			plurals[1] + ' not saved. Use options instead.'

	res.end JSON.stringify(instance)

app.post '/widgets_get', (req, res) ->
	id = JSON.parse(req.body.data)[0][0]
	widget = makeWidget id

	res.send JSON.stringify([widget])

app.post '/question_set_get', (req, res) ->
	id = JSON.parse(req.body.data)[0]

	# load instance, fallback to demo
	try
		res.send fs.readFileSync(path.join(qsets, id+'.json')).toString()
	catch e
		res.send getWidgetDemo()

app.get '/package', (req, res) ->
	res.write getFile 'download_package.html'
	res.end()

app.get '/preview_blocked/:instance?', (req, res) ->
	instance = req.params.instance or 'demo'

	file = getFile 'preview_blocked.html'

	res.write templateSwap(file, 'instance', instance)
	res.end()

app.get '/questions/import/', (req, res) ->
	file = getFile 'question_importer.html'

	res.write templateSwap(file, 'port', port)
	res.end()

app.post '/questions_get/', (req, res) ->
	given = JSON.parse(req.body.data)

	# we selected specific questions
	if given[0]
		res.end JSON.stringify(getQuestion given[0])
	# we just want all of them from the given type
	else
		res.end JSON.stringify(getAllQuestions given[1])

app.post '/session_valid', (req, res) ->
	res.end()

app.post '/play_logs_save', (req, res) ->
	logs = JSON.parse(req.body.data)[1]
	console.log(logs)

	res.end("{ \"score\": 0 }")

app.get '/assets/*', (req, res) ->
	res.write getFile('assets/'+req.params[0])
	res.end()

app.get '/build/*', (req, res) ->
	if path.extname(req.params[0]) is '.css'
		res.setHeader 'content-type', 'text/css'
	res.write getFile(req.params[0])
	res.end()

app.get '/showfiles', (req, res) ->
	middleware.fileSystem.readdir config.output.publicPath, (err, files) ->
		console.log files
	res.end()


###
File loading/manipulation support functions
###

getFile = (file) ->
	try
		# pull the specified filename out of memory
		middleware.fileSystem.readFileSync path.join(config.output.publicPath, file)
	catch e
		console.log 'error trying to load '+file

templateSwap = (file, target, replace) ->
	# stringify the given file buffer and replace all instances of 'target' with 'replace'
	str = file.toString()
	re = new RegExp '{{' + target + '}}', 'g'
	# if replacing 'target' with null, take extra steps to ensure it is actually 'null' and not the string '"null"'
	if replace is null
		re = new RegExp '(\'|"){{' + target + '}}(\'|")', 'g'

	Buffer.from str.replace(re, replace)

###
Widget creation/management support functions
###

getWidgetTitle = ->
	install = getFile 'install.yaml'
	yaml.parse(install.toString()).general.name

makeWidgetInstance = (id) ->
	qset = null
	widget = null
	widgetPath = null

	# attempt to load a previously saved instance with the given ID
	try
		return JSON.parse fs.readFileSync(path.join(qsets, id+'.instance.json')).toString()
	catch e

	# generate a new instance with the given ID
	try
		qset = JSON.parse getFile('demo.json').toString()
		widget = makeWidget id
	catch e
		console.log 'Error in makeInstance from the widget.coffee file:'
		console.log e

	[{
		'attempts': '-1',
		'clean_name': '',
		'close_at': '-1',
		'created_at': '1406649418',
		'embed_url': '',
		'height': 0,
		'id': '',
		'is_draft': true,
		'name': qset.name,
		'open_at': '-1',
		'play_url': '',
		'preview_url': '',
		'qset': {
		  'version': null,
		  'data': null
		},
		'user_id': '1',
		'widget': widget,
		'width': 0
	}]

makeWidget = (id) ->
	widget = yaml.parse getFile('install.yaml').toString()

	widget.player = widget.files.player
	widget.creator = widget.files.creator
	widget.clean_name = widget.general.name.replace(new RegExp(' ', 'g'), '-').toLowerCase()
	widget.dir = widget.clean_name + '/'
	widget.width = widget.general.width
	widget.height = widget.general.height
	widget

getWidgetDemo = ->
	JSON.stringify JSON.parse(getFile('demo.json').toString()).qset

###
Question importer support functions
###

# goes through the master list of default questions and filters according to a given type/types
getAllQuestions = (type) ->
	type = type.replace('Multiple%20Choice', 'MC')
	type = type.replace('Question%2FAnswer', 'QA')
	types = type.split(',')

	qlist = []

	obj = JSON.parse fs.readFileSync(path.join(__dirname, 'devmateria_questions.json')).toString()
	i = 1

	qarr = obj.set
	for q in qarr
		q.id = i++
		continue unless q.type in types
		qlist.push
			id: q.id
			type: q.type
			text: q.questions[0].text
			uses: Math.round(Math.random() * 1000)
			created_at: Date.now()

	return qlist

# pulls a question/questions out of the master list of default questions according to specified ID/IDs
getQuestion = (ids) ->
	# convert the given ids to numbers
	ids = ids.map (id) ->
		+id

	qlist = []

	obj = JSON.parse fs.readFileSync(path.join(__dirname, 'devmateria_questions.json')).toString()
	i = 1

	qarr = obj.set
	for q in qarr
		q.id = i++
		continue unless +q.id in ids
		qlist.push
			id: q.id
			type: q.type
			created_at: Date.now()
			questions: q.questions
			answers: q.answers
			options: q.options
			assets: q.assets

	return qlist
