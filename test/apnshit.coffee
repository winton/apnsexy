Apnshit = require('../lib/apnshit')
fs      = require('fs')
_       = require('underscore')

apns          = null
config        = null
device_id     = null
notifications = []

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
      'connect#start'
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
      'socketData#resend'
      'watchForStaleSocket#start'
      'watchForStaleSocket#interval_start'
      'watchForStaleSocket#stale'
      'watchForStaleSocket#stale#no_response'
      'watchForStaleSocket#stale#intentional_bad_notification'
    ]

    _.each events, (e) =>
      apns.on e, => console.log(e)

  describe '#connect()', ->
    it 'should connect', (done) ->
      apns.connect().then(-> done())

  describe '#send()', ->
    it 'should send a notification', (done) ->
      apns.send(notification()).then(
        (n) ->
          notifications.push(n)
          done()
      )

    it 'should recover from failure', (done) ->
      errors = 0
      promise = apns.send(notification(true))

      for i in [0..8]
        promise.then(
          => apns.send(notification(true))
        )
      
      promise.then(
        => apns.send(notification())
      ).then(
        (n) -> notifications.push(n)
      )
      
      apns.on 'error', (n) =>
        errors += 1
        process.stdout.write('.')
      
      apns.on 'done', =>
        console.log('errors', errors)
        errors.should.equal(10)
        done()

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      for n in notifications
        console.log("\n#{n.alert}")
      done()