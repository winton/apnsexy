Apnshit = require('../lib/apnshit')
apns = null

describe 'Apnshit', ->

  before ->
    apns = new Apnshit(
      "cert": "/Users/wintonwelsh/Sites/namtar/config/apns-development.pem"
      "key": "/Users/wintonwelsh/Sites/namtar/config/apns-development.pem"
      "gateway": "gateway.sandbox.push.apple.com"
      "port": "2195"
      "enhanced": true
      "cacheLength": "1000"
    )

  describe '#connect()', ->
    it 'should connect', (done) ->
      apns.connect().then(-> done())

  describe '#send()', ->
    it 'should', (done) ->
      noti = new apns.Notification()
      noti.alert = "This is a test"
      noti.badge = 0
      noti.sound = 'default'
      noti.device = '91c5edb38fff5524370350b3e686e303f835d2a27967fed5b53f8c63513ae132'
      apns.send(noti)