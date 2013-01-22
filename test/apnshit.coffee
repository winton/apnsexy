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
    apns   = new Apnshit(
      cert          : config.cert
      key           : config.key
      gateway       : "gateway.sandbox.push.apple.com"
      port          : 2195
      resend_on_drop: true
    )

    events = [
      #'connect#start'
      'connect#exists'
      'connect#connecting'
      'connect#connected'
      'disconnect#start'
      'disconnect#drop'
      'disconnect#drop#resend'
      'disconnect#drop#nothing_to_resend'
      'disconnect#finish'
      'send#start'
      'send#connected'
      'send#write'
      'send#write#finish'
      'socketData#start'
      'socketData#found_intentional_bad_notification'
      'socketData#found_notification'
      'watchForStaleSocket#start'
      'watchForStaleSocket#interval_start'
      'watchForStaleSocket#stale'
      'watchForStaleSocket#stale#no_response'
      'watchForStaleSocket#stale#intentional_bad_notification'
    ]

    _.each events, (e) =>
      apns.on e, (a, b) =>
        if e == 'send#write'
          console.log(e, a.alert)
        else if e == 'socketData#invalid_token#notification'
          console.log(e, a.alert)
        else if e == "disconnect#drop#resend"
          console.log(e, a.length)
        else if e == "socketData#start"
          console.log(e, a[0])
        else if e == "disconnect#start"
          console.log(e, JSON.stringify(a))
        else
          console.log(e)

  describe '#connect()', ->
    it 'should connect', (done) ->
      apns.connect().then(-> done())

  describe '#send()', ->
    it 'should send a notification', (done) ->
      apns.send(notification()).then(
        (n) -> notifications.push(n)
      )
      apns.once 'finish', => done()

    it 'should recover from failure', (done) ->
      bad             = []
      drops           = 0
      errors          = []
      expected_errors = 0
      good            = []
      sample          = 200
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
      
      apns.on 'error', (n) =>
        errors.push(n)
        process.stdout.write('b')

      apns.on 'success', (n) =>
        success.push(n)
        process.stdout.write('g')

      apns.on 'watchForStaleSocket#stale#no_response', =>
        drops += 1
      
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