#apnshit

Node.js APNS library that tries not to be as shitty as APNS.

##Install

	npm install apnshit -g

##Events

###finish(total_sent, potential_drops)

Emits when there are not any notifications to be resent.

###error(notification)

Emits when an invalid token is found.

###sent(notification)

Emits when a notification is sent down the wire.