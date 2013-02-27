for key, value of require('../lib/apnsexy/common')
  eval("var #{key} = value;")

for key, value of require('./helpers')
  eval("var #{key} = value;")

apnsexy = require('../lib/apnsexy')
fs      = require('fs')
_       = require('underscore')

Apnsexy = apnsexy.Apnsexy
Librato = apnsexy.Librato

apns              = null
bad               = []
config            = null
device_id         = null
drops             = 0
errors            = []
expected_drops    = 0
expected_errors   = 0
expected_finishes = 0
expected_sent     = 0
finishes          = 0
good              = []
librato           = null
notifications     = []
sample            = process.env.SAMPLE || 6
sample            = parseInt(sample)
sent              = 0

if sample < 6
  console.log "SAMPLE must be greater than 5"
  process.exit()

describe 'Apnsexy', ->

  beforeEach ->
    bad    = []
    drops  = 0
    errors = []
    good   = []
    sent   = 0

    expected_drops  = 0
    expected_errors = 0
    expected_sent   = 0

  before ->
    config  = fs.readFileSync("#{__dirname}/config.json")
    config  = JSON.parse(config)
    librato = new Librato(config.librato)

    apns = new Apnsexy(
      cert          : config.cert
      debug         : true
      debug_ignore  : [
        'enqueue'
        'connect#connecting'
        #'connect#connected'
        'connect#start'
        'connect#exists'
        'send#start'
        'keepSending'
        'send#write'
        'send#written'
        'socketData#start'
      ]
      key    : config.key
      gateway: "gateway.sandbox.push.apple.com"
      librato: librato
    )

    apns.on 'debug', console.log

    apns.on 'error', (n) =>
      errors.push(n)

    apns.on 'finish', (counts) =>
      drops     = counts.potential_drops
      sent      = counts.total_sent
      finishes += 1

      console.log "\n"
      console.log    "         (actual / expected)"
      console.log "sent    :", "#{sent} / #{expected_sent}"
      console.log "drops   :", "#{drops} / #{expected_drops}"
      console.log "finishes:", "#{finishes} / #{expected_finishes}"
      console.log "errors  :", "#{errors.length} / #{expected_errors}"
      console.log "\n"

      drops.should.equal(expected_drops)
      errors.length.should.equal(expected_errors)
      finishes.should.equal(expected_finishes)
      sent.should.equal(expected_sent)

  if process.env.GOOD
    describe '#connect()', ->
      it 'should connect', (done) ->
        apns.connect().then(=> done())

    describe '#enqueue()', ->
      it 'should send a notification', (done) ->
        expected_sent = 1
        expected_finishes++

        n = notification()
        notifications.push(n)
        
        apns.once 'finish', => done()
        apns.enqueue(n)

  describe '#enqueue()', ->
    if process.env.BAD
      it 'should recover from failure (mostly bad)', (done) ->
        apns.once 'finish', => done()
        send('mostly bad')

        expected_sent = good.length
        expected_finishes++

      it 'should recover from failure (all bad)', (done) ->
        apns.once 'finish', => done()
        send('all bad')

        expected_sent = good.length
        expected_finishes++

      it "should recover from socket error mid-way through", (done) ->
        # drop drop error bad good bad

        error_at = Math.floor(sample / 2) - 1
        writes   = 0

        expected_drops   = error_at + 1
        expected_errors -= error_at
        expected_sent    = 1
        expected_finishes++

        apns.on 'sent', =>
          if writes == error_at
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

      it "should recover from socket error mid-way through (twice)", (done) ->
        # drop drop error error good bad

        error_at = Math.floor(sample / 2) - 1
        writes   = 0

        expected_drops   = error_at * 2
        expected_errors -= error_at * 2 - 1
        expected_sent    = 1
        expected_finishes++

        apns.on 'sent', =>
          if writes == error_at || writes == error_at * 2 - 1
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

      it 'should timeout on failed connection', (done) ->
        expected_drops    += sample
        expected_errors   -= sample
        expected_sent      = 0
        expected_finishes++

        # Stub out connection so it never connects
        apns.connecting = true
        apns.connect_promise = defer (resolve, reject) -> resolve()

        apns.once 'finish', => done()
        send('all bad')

    if process.env.GOOD
      it 'should recover from error (mostly good)', (done) ->
        apns.once 'finish', => done()
        send('mostly good')

        expected_sent = good.length
        expected_finishes++

      it 'should send multiple (all good)', (done) ->
        apns.once 'finish', => done()
        send('all good')

        expected_sent = good.length
        expected_finishes++

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      console.log('')

      ns = _.map notifications, (n) =>
        n.alert.replace(/\D+/g, '')

      console.log("\n#{ns.length} notifications:")
      console.log("\n#{ns.join("\n")}")

      librato.on('finish', => done())

send = (type) ->
  for i in [0..sample-1]
    if type == 'all good'
      is_good = true
    else if type == 'all bad'
      is_good = false
    else if type == 'mostly good'
      is_good = i != 1 && i != sample - 2
    else if type == 'mostly bad'
      is_good = i == 1 || i == sample - 2

    n = notification(i, !is_good)

    if is_good
      good.push(n)
      notifications.push(n)
    else
      expected_errors += 1
      bad.push(n)

    apns.enqueue(n)