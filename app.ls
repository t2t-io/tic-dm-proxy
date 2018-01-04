#!/usr/bin/env lsc
#
require! <[http]>
require! <[colors yargs express body-parser request mdns]>

const PORT = 7070

START_BONJOUR_ADVERTISEMENT = ->
  ad = mdns.createAdvertisement (mdns.tcp \http), PORT
  ad.start!
  console.log "broadcasting http server running at port #{PORT} ..."

ERR_EXIT = (message) ->
  console.error message
  process.exit 1


argv = yargs
  .alias \b, \batch
  .describe \b, 'the batch number for TOE identity generation'
  .alias \u, \user
  .describe \u, 'the username to login TIC DM server'
  .alias \p, \password
  .describe \p, 'the password to login TIC DM server'
  .alias \s, \server
  .describe \s, 'the url of TIC DM server'
  .default \s, 'https://tic-dm.t2t.io'
  .demandOption <[batch user password server]>
  .example """
    ./app --batch 12 --user conscious-mp-agent --password abcd1234
  """
  .strict!
  .help!
  .argv

{batch, user, password, server} = argv
batch-number = parse-int batch
return ERR_EXIT "invalid batch number: #{batch}" if batch-number === NaN

url = "#{server}/api/v3/me"

(request-err, response, body) <- request url: url, auth: {user, password}
return ERR_EXIT "failed to access #{url}, err: #{request-err}" if request-err?
return ERR_EXIT "invalid response code: #{response.statusCode}" unless response.statusCode is 200
text = "#{body}"
config = JSON.parse text
profiles = [ k for k, v of config.data.permissions ]
console.log "allow to access #{profiles.join ', '}"

app = express!
app.use body-parser.json!

app.post '/api/v3/nodes/:profile/create-production-node/:serial_number', (req, res) ->
  {params, body} = req
  {profile, serial_number} = params
  {device, version, macaddr_eth, macaddr_usb, macaddr_wlan} = body
  url = "/api/v3/nodes/#{profile}/create-production-node/#{serial_number}"
  console.log "toe => proxy: #{url.cyan}, body: #{(JSON.stringify body)}"
  return res.status 404 .send "profile #{profile} is unacceptable" .end! unless profile in profiles
  batch = batch-number
  opts =
    url: "#{argv.server}#{url}"
    method: \POST
    auth: {user, password}
    json: yes
    body: {device, version, macaddr_eth, macaddr_usb, macaddr_wlan, batch}
  console.log "proxy => tic: #{url.cyan}, user: #{user.yellow}, body: #{(JSON.stringify opts.body).green}"
  (err, rsp, body) <- request opts
  return res.status 400 .send "err: #{err}" .end! if err?
  console.log "proxy <= tic: #{url.cyan}, body: #{(JSON.stringify body).magenta}"
  return res.status rsp.statusCode .json body .end!

server = http.createServer app
server.on \listening ->
  console.log "listening port #{PORT} ..."
  return START_BONJOUR_ADVERTISEMENT!
server.listen PORT, '0.0.0.0'
