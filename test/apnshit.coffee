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
      ((new Date).getTime() + '').substr(-4)
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
      "cert": config.cert
      "key": config.key
      "gateway": "gateway.sandbox.push.apple.com"
      "port": "2195"
      "enhanced": true
      "cacheLength": "1000"
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
      apns.send(notification(true))
      apns.send(notification()).then(
        (n) ->
          notifications.push(n)
          done()
      )

  describe 'verify notifications', ->
    it 'should have sent these notifications', (done) ->
      for n in notifications
        console.log("\n#{n.alert}")