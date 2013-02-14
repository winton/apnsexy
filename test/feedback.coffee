for key, value of require('../lib/apnshit/common')
  eval("var #{key} = value;")

for key, value of require('./helpers')
  eval("var #{key} = value;")

apnshit = require('../lib/apnshit')
fs      = require('fs')
_       = require('underscore')

Apnshit      = apnshit.Apnshit
Feedback     = apnshit.Feedback
Notification = apnshit.Notification

cert            = null
config          = null
device_id       = null
feedback        = null

if process.env.FEEDBACK
  describe 'Feedback', ->

    before (done) ->
      config = fs.readFileSync("#{__dirname}/config.json")
      config = JSON.parse(config)

      cert = "/Users/wintonwelsh/Sites/namtar/config/apns-production.pem"

      apns = new Apnshit(
        cert          : cert
        debug         : true
        debug_ignore  : [ 'connect#start', 'keepSending', 'send#start' ]
        key           : cert
        gateway       : "gateway.push.apple.com"
      )

      apns.on 'debug', console.log

      apns.enqueue(notification("ee1a4015086fad0da5705bddc803233297f834fb5b5e55ca524421069fe44537"))
      apns.enqueue(notification("7a4be145692158ee5a1f275cccc7fd83fed7f744c9837f04c5db23e104bea391"))
      apns.once 'finish', => done()

    describe 'feedback event', ->
      it 'should emit', (done) ->
        feedback = new Feedback(
          address       : "feedback.push.apple.com"
          cert          : cert
          debug         : true
          debug_ignore  : [ 'connect#start' ]
          interval      : 5
          key           : cert
        )

        feedback.on 'debug', console.log