Apnshit = require('../lib/apnshit')
fs      = require('fs')
_       = require('underscore')

apns            = null
bad             = []
config          = null
device_id       = null
drops           = null
errors          = []
expected_errors = null
good            = []
notifications   = []
sample          = null
success         = []

notification = (bad = false) ->
  noti = new apns.Notification()
  noti.alert =
    "#{
      if bad then "Bad" else "Good"
    } notification: #{
      Math.floor(Math.random()*10000)
    }"
  noti.badge = 0
  noti.sound = 'default'
  if bad
    noti.device = "#{
      Math.floor(Math.random() * (99999 - 10000 + 1)) + 10000
    }#{
      config.device_id.substr(5)
    }"
  else
    noti.device = config.device_id
  noti

describe 'Apnshit', ->

  before ->
    config = fs.readFileSync("#{__dirname}/config.json")
    config = JSON.parse(config)

    apns = new Apnshit(
      cert          : config.cert
      debug         : true
      debug_ignore  : [ 'connect#start', 'send#start' ]
      key           : config.key
      gateway       : "gateway.sandbox.push.apple.com"
      port          : 2195
      resend_on_drop: true
    )

    apns.on 'debug', console.log

    apns.on 'error', (n) =>
      errors.push(n)
      process.stdout.write('b')

    apns.on 'success', (n) =>
      success.push(n)
      process.stdout.write('g')

    apns.on 'watchForStaleSocket#stale#no_response', =>
      drops += 1

  describe '#connect()', ->
    it 'should connect', (done) ->
      apns.connect().then(-> done())

  describe '#send()', ->
    it 'should send a notification', (done) ->
      apns.send(notification()).then(
        (n) -> notifications.push(n)
      )
      apns.once 'finish', => done()

    it 'should recover from failure (mostly bad)', (done) ->
      bad             = []
      drops           = 0
      errors          = []
      expected_errors = 0
      good            = []
      sample          = 500
      success         = []

      for i in [0..sample-1]
        is_bad = Math.floor(Math.random()*sample*0.5) != 1
        n = notification(is_bad)
        if is_bad
          expected_errors += 1
          bad.push(n)
        else
          good.push(n)
          notifications.push(n)
        apns.send(n)
      
      apns.once 'dropped', =>
        done()

      apns.once 'finish', =>
        errors.length.should.equal(expected_errors)
        done()

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      console.log('')

      bad_diff  = _.filter bad,    (n) => errors.indexOf(n) == -1
      good_diff = _.filter good,   (n) => success.indexOf(n) == -1
      bad_diff  = _.map bad_diff,  (n) => n.alert
      good_diff = _.map good_diff, (n) => n.alert

      notifications = _.map notifications, (n) =>
        n.alert.replace(/\D+/g, '')

      console.log(
        "\nmissed success events:",
        if good_diff.length then good_diff.join(", ") else "none!"
      )

      console.log(
        "\nmissed error events:",
        if bad_diff.length then bad_diff.join(", ") else "none!"
      )
      console.log("\nsample size: #{sample}")
      console.log("\ndrops: #{drops}")
      console.log("\n#{errors.length} errors / #{expected_errors} expected")
      console.log("\n#{notifications.length} notifications:")
      console.log("\n#{notifications.join("\n")}")

      done()