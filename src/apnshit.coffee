for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

module.exports = class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @Notification = require './apnshit/notification'

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
          else
            @emit('debug', e)

  connect: ->
    @emit('connect#start', @connect_promise)

    @connect_promise ||= @defer (resolve, reject) =>
      if @socket && @socket.writable
        @emit('connect#exists')
        resolve()
      else
        @emit('connect#connecting')
        @connecting = true
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.reject_unauthorized
          socket            : new net.Stream()

        @socket = tls.connect @options.port, @options.gateway, socket_options, =>
          resolve()
          delete @connect_promise
          @emit("connect#connected")
          @watchForStaleSocket()

        @socket.on "data", (data) => @socketData(data)
        @socket.on "error",   (e) =>
          @emit("socket#error", e)
          @disconnect(drop: true)

        # @socket.setKeepAlive(true)
        # @socket.setTimeout(@options.timeout, => console.log('timeout!'))
        # @socket.setNoDelay(false)

        @socket.socket.connect @options.port, @options.gateway

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

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
    'send#start'
    'send#connected'
    'send#write'
    'send#write#finish'
    'socket#error'
    'socketData#start'
    'socketData#found_intentional_bad_notification'
    'socketData#found_notification'
    'watchForStaleSocket#start'
    'watchForStaleSocket#interval_start'
    'watchForStaleSocket#stale'
    'watchForStaleSocket#stale#no_response'
    'watchForStaleSocket#stale#intentional_bad_notification'
  ]

  disconnect: (options = {}) ->
    @emit("disconnect#start", options)

    delete @bad_alert_sent
    delete @bytes_read
    delete @bytes_written
    delete @connect_promise
    delete @stale_count

    @socket.destroy()
    delete @socket

    clearInterval(@interval) if @interval

    if options.drop
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
        
        @not_sure_if_sent   = []
        @last_resend_uids ||= []

        resend_uids = _.map resend, (n) => n._last_uid

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
        
        @emit("disconnect#drop#resend", resend)
        
        @last_resend_uids = _.map resend, (n) => n._uid

        # exponential backoff
        setTimeout(
          => @send(item) for item in resend
          500 * @infinite_resend_count
        )
      else
        @emit("disconnect#drop#nothing_to_resend")
        @emit("finish")
    else
      @emit("disconnect#finish")
      @emit("finish")
      @not_sure_if_sent = []

  send: (notification) ->
    @emit("send#start", notification)

    @current_id       ||= 0
    @not_sure_if_sent ||= []

    data           = undefined
    encoding       = notification.encoding || "utf8"
    message        = JSON.stringify(notification)
    message_length = Buffer.byteLength(message, encoding)
    position       = 0
    token          = new Buffer(notification.device.replace(/\s/g, ""), "hex")
  
    @connect().then(
      =>
        @emit("send#connected", notification)

        notification._last_uid = notification._uid
        notification._uid      = @current_id++

        @current_id = 0  if @current_id > 0xffffffff

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

        @not_sure_if_sent.push(notification)

        @defer (resolve, reject) =>
          @emit('send#write', notification)
          @socket.write data, encoding, =>
            @emit('send#write#finish', notification)
            resolve(notification)
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
        @emit('watchForStaleSocket#interval_start')        

        if @socket && !@socket.writable
          @disconnect(drop: true)
          return

        return unless @socket && @socket.writable

        stale = (
          @socket.bytesRead    == @bytes_read &&
          @socket.bytesWritten == @bytes_written
        )

        @emit('watchForStaleSocket#stale', stale)

        if stale
          @stale_count ||= 0
          @stale_count++

          if @bad_alert_sent
            @emit('watchForStaleSocket#stale#no_response')
            @disconnect(drop: true)
          else if @stale_count == 2
            @emit('watchForStaleSocket#stale#intentional_bad_notification')

            noti = new @Notification()
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