#Apnsexy

Test-driven APNS library with built-in metrics.

##Install

    npm install apnsexy -g

##Example (coffeescript)

    apnsexy = require("apnsexy")
    Apnsexy = apnsexy.Apnsexy
    Librato = apnsexy.Librato

    # Librato Metrics
    librato = new Librato(
      "email": "your@email.com",
      "token": "yourtoken"
    )

    # Apnsexy
    apns = new Apnsexy(
      cert          : "/path/to/cert.pem"
      debug         : true
      debug_ignore  : [ "keepSending" ]
      gateway: "gateway.sandbox.push.apple.com"
      librato: librato
    )

    # Send notification
    apns.enqueue(
      new Notification(
        alert : "hello!"
        badge : 0
        device: "deviceidgoeshere"
      )
    )

##Apnsexy Instance Events

###error(notification)

Emits when an invalid token (error 8) is found.

###finish(total_sent, potential_drops)

Emits when there are not any notifications to be resent.

###sent(notification)

Emits once a notification is sent down the wire.