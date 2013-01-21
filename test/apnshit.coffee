Apnshit = require('../lib/apnshit')
fs      = require('fs')
_       = require('underscore')

apns            = null
config          = null
device_id       = null
errors          = null
expected_errors = null
notifications   = []
sample          = null

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
      'send#write'
      'send#write#finish'
      'socketData#start'
      'socketData#invalid_token'
      'socketData#invalid_token#intentional_bad_notification'
      'socketData#invalid_token#notification'
      'socketData#invalid_token#resend'
      'socketData#invalid_token#nothing_to_resend'
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
      errors          = 0
      expected_errors = 0
      promise         = apns.send(notification())
      sample          = 40

      for i in [0..sample-2]
        promise.then(
          =>
            bad = Math.floor(Math.random()*sample*0.2) != 1
            expected_errors += 1 if bad
            n = notification(bad)
            notifications.push(n) unless bad
            apns.send(n)
        )
      
      promise.then(
        (n) -> notifications.push(n)
      )
      
      apns.on 'error', (n) =>
        errors += 1
        process.stdout.write('.')
      
      apns.once 'finish', =>
        errors.should.equal(expected_errors)
        done()

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      notifications = _.map notifications, (n) =>
        n.alert.replace(/\D+/g, '')
      console.log("\n#{notifications.sort().join("\n")}")
      console.log("\n#{errors} errors")
      console.log("\n#{notifications.length} notifications")
      console.log("\n#{sample} sample size")
      done()