for key, value of require('../lib/apnshit/common')
  eval("var #{key} = value;")

for key, value of require('./helpers')
  eval("var #{key} = value;")

apnshit = require('../lib/apnshit')
fs      = require('fs')
_       = require('underscore')

Apnshit = apnshit.Apnshit

apns              = null
bad               = []
config            = null
device_id         = null
drops             = 0
errors            = []
expected_drops    = 0
expected_errors   = 0
expected_finishes = 0
finishes          = 0
good              = []
notifications     = []
sample            = process.env.SAMPLE || 6

if sample < 6
  console.log "SAMPLE must be greater than 5"
  process.exit()

describe 'Apnshit', ->

  before ->
    config = fs.readFileSync("#{__dirname}/config.json")
    config = JSON.parse(config)

    apns = new Apnshit(
      cert          : config.cert
      debug         : true
      debug_ignore  : [
        'enqueue'
        #'connect#connecting'
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
      librato: config.librato
    )

    apns.on 'debug', console.log

    apns.on 'error', (n) =>
      errors.push(n)

    apns.on 'finish', (sent, drop_count) =>
      drops += drop_count
      finishes += 1

      console.log "sent", sent
      console.log "drop count", drop_count
      console.log "drops", drops
      console.log "expected drops", expected_drops
      console.log "finishes", finishes
      console.log "expected finishes", expected_finishes
      console.log "errors.length", errors.length
      console.log "expected errors", expected_errors

      drops.should.equal(expected_drops)
      errors.length.should.equal(expected_errors)
      finishes.should.equal(expected_finishes)

  if process.env.GOOD
    describe '#connect()', ->
      it 'should connect', (done) ->
        apns.connect().then(=> done())

    describe '#enqueue()', ->
      it 'should send a notification', (done) ->
        expected_finishes += 1

        n = notification()
        
        apns.once 'finish', => done()
        apns.enqueue(n)
        
        notifications.push(n)

  describe '#enqueue()', ->
    if process.env.BAD
      it 'should recover from failure (mostly bad)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('mostly bad')

      it 'should recover from failure (all bad)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('all bad')

      it "should recover from socket error mid-way through", (done) ->
        error_at           = Math.floor(sample / 2) - 1
        expected_drops    += error_at + 1
        expected_finishes += 1
        writes             = 0

        # The drops will not trigger an error event as normally expected.
        # We need to decrement those drops from the expected errors variable.
        expected_errors -= error_at

        apns.on 'sent', =>
          if writes == error_at
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

      it "should recover from socket error mid-way through (twice)", (done) ->
        error_at           = Math.floor(sample / 2) - 1
        expected_drops    += error_at * 2
        expected_errors   -= error_at * 2 - 1
        expected_finishes += 1
        writes             = 0

        apns.on 'sent', =>
          if writes == error_at || writes == error_at * 2 - 1
            apns.socket.destroy()
          writes++

        apns.once 'finish', => done()
        send('mostly bad')

    if process.env.GOOD
      it 'should recover from error (mostly good)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('mostly good')

      it 'should send multiple (all good)', (done) ->
        expected_finishes += 1
        apns.once 'finish', => done()
        send('all good')

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      console.log('')

      notifications = _.map notifications, (n) =>
        n.alert.replace(/\D+/g, '')

      errors = _.map errors, (n) =>
        n.alert.replace(/\D+/g, '')

      console.log("\nsample size: #{sample}")
      console.log("\ndrops: #{drops}")
      console.log("\n#{errors.length} errors / #{expected_errors} expected")
      console.log("\n#{notifications.length} notifications:")
      console.log("\n#{notifications.join("\n")}")

      # allow librato requests to finish
      setTimeout(
        => done()
        1000
      )

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