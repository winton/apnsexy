for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

Feedback     = require './apnshit/feedback'
Notification = require './apnshit/notification'

class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @current_id    = 0
    @notifications = []
    
    @options =
      ca                   : null
      cert                 : 'cert.pem'
      debug                : false
      debug_ignore         : []
      enhanced             : true
      gateway              : 'gateway.push.apple.com'
      infinite_resend_limit: 10
      key                  : 'key.pem'
      passphrase           : null
      port                 : 2195
      reject_unauthorized  : true

    _.extend(@options, options)

    @on "error", ->

    @attachDebugEvents() if @options.debug
    @keepSending()

  attachDebugEvents: ->
    _.each @events, (e) =>
      @on e, (a, b) =>
        return if @options.debug_ignore.indexOf(e) >= 0
        if e == 'send#write'
          @emit('debug', e, a.alert)
        else if e == 'socketData#invalid_token#notification'
          @emit('debug', e, a.alert)
        else if e == "disconnect#drop#resend"
          @emit('debug', e, a.length)
        else if e == "socketData#start"
          @emit('debug', e, a[0])
        else if e == "socket#error"
          @emit('debug', e, a)
        else
          @emit('debug', e)

  connect: ->
    @emit('connect#start')

    defer (resolve, reject) =>
      if @socket && @socket.writable
        @emit('connect#exists')
        resolve()
      else
        @emit('connect#connecting')
        
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.reject_unauthorized
          socket            : new net.Stream()
    
        @socket = tls.connect @options.port, @options.gateway, socket_options, =>
          @emit("connect#connected")
          delete @connect_promise
          resolve()

        @socket.on "close", @socketError
        @socket.on "data" , @socketData
        @socket.on "error", @socketError

        @socket.setNoDelay(false)
        @socket.socket.connect @options.port, @options.gateway

  enqueue: (notification) ->
    @notifications.push(notification)

  keepSending: ->
    process.nextTick(
      => send() if !@sending && @notifications.length
    )

  send: ->
    notification = @notifications.shift()

    if notification
      @sending = true
      @emit("send#start", notification)

      @current_id = 0  if @current_id > 0xffffffff
      notification._uid = @current_id++

      data           = undefined
      encoding       = notification.encoding || "utf8"
      message        = JSON.stringify(notification)
      message_length = Buffer.byteLength(message, encoding)
      position       = 0
      token          = new Buffer(notification.device.replace(/\s/g, ""), "hex")

      if @options.enhanced
        data = new Buffer(1 + 4 + 4 + 2 + token.length + 2 + message_length)
        data[position] = 1
        position++
        data.writeUInt32BE notification._uid, position
        position += 4
        data.writeUInt32BE notification.expiry, position
        position += 4
      else
        data = new Buffer(1 + 2 + token.length + 2 + message_length)
        data[position] = 0
        position++
      
      data.writeUInt16BE token.length, position
      position += 2
      position += token.copy(data, position, 0)
      
      data.writeUInt16BE message_length, position
      position += 2
      position += data.write(message, position, encoding)
      
      @connect().then(
        =>
          @socket.write data, encoding, =>
            @sending = false
            notification._written = true
      )

  socketData: (data) ->
    @emit('socketData#start', data)

    error_code = data[0]
    identifier = data.readUInt32BE(2)

    notification = _.find @notifications, (item, i) =>
      item._uid == identifier
    
    if notification
      @emit('socketData#found_notification', notification)
      @emit('error', notification)  if error_code == 8

      @notifications = @notifications.slice(
        @notifications.indexOf(notification) + 1
      )

  socketError: ->
    @notifications = _.reject(@notifications, (n) => n._written)