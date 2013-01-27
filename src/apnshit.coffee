for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

Feedback     = require './apnshit/feedback'
Notification = require './apnshit/notification'

class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @on "error", ->
    
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
      resend_on_drop       : true
      timeout              : 2000
      reject_unauthorized  : true

    _.extend @options, options

    if @options.debug
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

    @reset(socket: false)

  connect: ->
    @emit('connect#start', @connect_promise)

    @connect_promise ||= defer (resolve, reject) =>
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
          delete @connect_promise
          @watchForStaleSocket()
          resolve()
          @emit("connect#connected")

        @socket.on "data" , (data) => @socketData(data)
        @socket.on "error",   (e) =>
          @emit("socket#error", e)
          @disconnect()

        @socket.setNoDelay(false)
        @socket.socket.connect @options.port, @options.gateway

  events: [
    'connect#start'
    'connect#exists'
    'connect#connecting'
    'connect#connected'
    'disconnect#start'
    'disconnect#drop'
    'disconnect#drop#infinite_resend'
    'disconnect#drop#infinite_resend#limit_reached'
    'disconnect#drop#resend'
    'disconnect#drop#nothing_to_resend'
    'disconnect#finish'
    'reset#start'
    'reset#socket'
    'reset#socket#close'
    'send#start'
    'send#connected'
    'send#write'
    'send#write#finish'
    'socket#error'
    'socketData#start'
    'socketData#found_intentional_bad_notification'
    'socketData#found_notification'
    'watchForStaleSocket#start'
    'watchForStaleSocket#interval#start'
    'watchForStaleSocket#interval#socket_not_writable'
    'watchForStaleSocket#interval#stale'
    'watchForStaleSocket#interval#stale#no_response'
    'watchForStaleSocket#interval#stale#intentional_bad_notification'
  ]

  disconnect: (options = {}) ->
    @emit("disconnect#start", options)
    
    if options.drop
      @reset(socket: true).then =>
        @emit("disconnect#drop", @not_sure_if_sent)

        if options.resend
          resend = (
            options.resend &&
            options.resend.length
          )
        else
          resend = (
            @options.resend_on_drop &&
            @not_sure_if_sent &&
            @not_sure_if_sent.length
          )

        if resend
          resend = options.resend || @not_sure_if_sent.slice()
          
          @emit("disconnect#drop#resend", resend)
          
          @not_sure_if_sent   = []
          @last_resend_uids ||= []

          resend_uids = _.map resend, (n) => n._last_uid || false

          if !(resend_uids < @last_resend_uids || @last_resend_uids < resend_uids)
          #  ^ equality test

            @emit("disconnect#drop#infinite_resend", resend)
            
            @infinite_resend_count ||= 0
            @infinite_resend_count++

            if @infinite_resend_count == @options.infinite_resend_limit
              @emit("disconnect#drop#infinite_resend#limit_reached", resend)
              @emit("dropped", resend)

              delete @last_resend_uids
              return
          else
            @infinite_resend_count = 0
          
          @last_resend_uids = _.map resend, (n) => n._uid

          # exponential backoff
          setTimeout(
            => @send(item) for item in resend
            500 * @infinite_resend_count
          )
        else
          @not_sure_if_sent = []
          @emit("disconnect#drop#nothing_to_resend")
          @emit("finish")
    else
      @emit("disconnect#finish")
      @emit("finish")

  reset: (options = {}) ->
    defer (resolve, reject) =>
      @emit("reset#start")

      @write_promise = defer (resolve, reject) => resolve()

      delete @bad_alert_sent
      delete @bytes_read
      delete @bytes_written
      delete @stale_count

      clearInterval(@interval) if @interval

      if options.socket
        @emit("reset#socket")
        delete @connect_promise
        if @socket
          @socket.once 'close', =>
            @emit("reset#socket#close")
            delete @socket
            resolve()
          @socket.destroy()
        else
          resolve()
      else
        resolve()

  send: (notification) ->
    @emit("send#start", notification)

    @current_id       ||= 0
    @not_sure_if_sent ||= []

    notification._last_uid = notification._uid
    notification._uid      = @current_id++

    unless notification.alert == 'x'
      @not_sure_if_sent.push(notification)

    @current_id = 0  if @current_id > 0xffffffff

    data           = undefined
    encoding       = notification.encoding || "utf8"
    message        = JSON.stringify(notification)
    message_length = Buffer.byteLength(message, encoding)
    position       = 0
    token          = new Buffer(notification.device.replace(/\s/g, ""), "hex")
  
    @connect().then(
      =>
        @emit("send#connected", notification)

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

        @write_promise.then(
          =>
            defer (resolve, reject) =>
              @emit('send#write', notification)
              @socket.write data, encoding, =>
                @emit('send#write#finish', notification)
                resolve(notification)
        )
    )

  socketData: (data) ->
    @emit('socketData#start', data)

    error_code = data[0]
    identifier = data.readUInt32BE(2)

    notification = _.find @not_sure_if_sent, (item, i) =>
      item._uid == identifier
    
    if notification
      if notification.alert == 'x'
        @emit('socketData#found_intentional_bad_notification')
        @disconnect()
      else
        @emit('socketData#found_notification', notification)
        @emit('error', notification) if error_code == 8

        resend = @not_sure_if_sent.slice(
          @not_sure_if_sent.indexOf(notification) + 1
        )

        @disconnect(drop: true, resend: resend)

  watchForStaleSocket: =>
    @emit('watchForStaleSocket#start')

    clearInterval(@interval) if @interval
    @interval = setInterval(
      =>
        @emit('watchForStaleSocket#interval#start')

        if @socket && !@socket.writable
          @emit('watchForStaleSocket#interval#socket_not_writable')
          @disconnect(drop: true)
          return

        return unless @socket && @socket.writable

        stale = (
          @socket.bytesRead    == @bytes_read &&
          @socket.bytesWritten == @bytes_written
        )

        @emit('watchForStaleSocket#interval#stale', stale)

        if stale
          @stale_count ||= 0
          @stale_count++

          if @bad_alert_sent
            @emit('watchForStaleSocket#interval#stale#no_response')
            @disconnect(drop: true)
          else if @stale_count == 2
            @emit('watchForStaleSocket#interval#stale#intentional_bad_notification')

            noti = new Notification()
            noti.alert  = "x"
            noti.badge  = 0
            noti.sound  = "default"
            noti.device = Array(32).join("a0")

            @bad_alert_sent = true

            @send(noti)

        if @socket
          @bytes_read    = @socket.bytesRead
          @bytes_written = @socket.bytesWritten
        else
          delete @bytes_read
          delete @bytes_written

      @options.timeout
    )

module.exports = 
  Apnshit     : Apnshit
  Feedback    : Feedback
  Notification: Notification
