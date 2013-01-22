#apnshit

Node.js APNS library that tries not to be as shitty as APNS.

##Install

	npm install apnshit -g

##Events

###debug(event, a, b, c, ...)

Emits when any event below fires. Can emit directly into console.log.

###connect#start(@connect_promise)

Emits immediately upon calling `connect()`.

###connect#exists

Emits when the socket is already writable, no need to connect.

###connect#connecting

Emits when connect logic begins.

###connect#connected

Emits when socket is connected.

###disconnect#start

Emits immediately upon calling `disconnect()`.

###disconnect#drop(@not_sure_if_sent)

Emits when this disconnect is the result of a dropped connection.

###disconnect#drop#infinite_resend(resend)

Emits when last resend is identical to the current one.

###disconnect#drop#infinite_resend#limit_reached(resend)

**Aliases: `drop`**

Emits when there have been `infinite_resent_limit` identical resends.

###disconnect#drop#resend(resend)

Emits when there are `@not_sure_if_sent` notifications to be resent.

###disconnect#drop#nothing_to_resend

**Aliases: `finish`**

Emits when there are not any `@not_sure_if_sent` notifications to be resent.

###disconnect#finish

**Aliases: `finish`**

Emits when `disconnect()` called without the drop option, meaning no further action will be taken on this connection.

###send#start(notification)

Emits immediately upon calling `send()`.

###send#connected(notification)

Emits after verifying the connection but before writing to the socket.

###send#write(notification)

Emits before a notification is written to the socket.

###send#write#finish(notification)

Emits after a notification is written to the socket.

###socketData#start(data)

Emits when the socket receives data.

###socketData#found_intentional_bad_notification

**Aliases: `finish`**

Emit when the invalid token was a result of an intentional bad notification to test connection status.

###socketData#found_notification(notification)

**Aliases: `error`**

Emits when the invalid notification is found within `@not_sure_if_sent`.

###socket#error(error)

Emits when the socket throws an error event.

###watchForStaleSocket#start

Emits immediately upon calling `watchForStaleSocket()`.

###watchForStaleSocket#interval_start

Emits when the interval function executes.

###watchForStaleSocket#stale(stale)

Emits when a stale connection is detected (no activity for the timeout period).

###watchForStaleSocket#stale#intentional_bad_notification

Emits immediately before intentionally sending a bad notification to check the connection status.

###watchForStaleSocket#stale#no_response

Emits when there is no response to an intentional bad notification after the timeout period.