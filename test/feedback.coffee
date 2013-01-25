# for key, value of require('../lib/apnshit/common')
#   eval("var #{key} = value;")

# apnshit = require('../lib/apnshit')
# fs      = require('fs')
# _       = require('underscore')

# Apnshit      = apnshit.Apnshit
# Feedback     = apnshit.Feedback
# Notification = apnshit.Notification

# cert            = null
# config          = null
# device_id       = null
# feedback        = null

# describe 'Feedback', ->

#   before (done) ->
#     config = fs.readFileSync("#{__dirname}/config.json")
#     config = JSON.parse(config)

#     cert = "/Users/wintonwelsh/Sites/namtar/config/apns-production.pem"

#     apns = new Apnshit(
#       cert          : cert
#       debug         : true
#       debug_ignore  : [ 'connect#start', 'send#start' ]
#       key           : cert
#       gateway       : "gateway.push.apple.com"
#       resend_on_drop: true
#     )

#     apns.on 'debug', console.log

#     apns.send(notification("ee1a4015086fad0da5705bddc803233297f834fb5b5e55ca524421069fe44537"))
#     apns.send(notification("7a4be145692158ee5a1f275cccc7fd83fed7f744c9837f04c5db23e104bea391"))
#     apns.once 'finish', => done()

#   describe 'feedback event', ->
#     it 'should emit', (done) ->
#       feedback = new Feedback(
#         address       : "feedback.push.apple.com"
#         cert          : cert
#         debug         : true
#         debug_ignore  : [ 'connect#start' ]
#         interval      : 5
#         key           : cert
#       )

#       feedback.on 'debug', console.log
#       feedback.on 'feedback', (time, device_id) =>
#         console.log('feedback!', time, device_id)

# # Helpers

# notification = (bad = false) ->
#   noti = new Notification()
#   noti.alert =
#     "#{
#       if bad then "Bad" else "Good"
#     } notification: #{
#       Math.floor(Math.random()*10000)
#     }"
#   noti.badge = 0
#   noti.sound = 'default'
#   if bad
#     noti.device = bad
#   else
#     noti.device = config.device_id
#   noti