Apnshit = require('../lib/apnshit')
fs = require('fs')

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
      Math.floor(Math.random()*1000)
    }"
  noti.badge = 0
  noti.sound = 'default'
  if bad
    noti.device = "0#{config.device_id.substr(1)}"
  else
    noti.device = config.device_id
  noti

describe 'Apnshit', ->

  before ->
    config = fs.readFileSync("#{__dirname}/config.json")
    config = JSON.parse(config)
    apns   = new Apnshit(
      cert   : config.cert
      key    : config.key
      gateway: "gateway.sandbox.push.apple.com"
      port   : 2195
      timeout: 1000
    )

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
        errors.should.equal(10)
        done()

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      for n in notifications
        console.log("\n#{n.alert}")
      done()