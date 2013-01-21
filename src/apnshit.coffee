for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

module.exports = class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @Notification = require './apnshit/notification'

    @on "error", ->
    
    @options =
      ca                : null
      cert              : 'cert.pem'
      enhanced          : true
      gateway           : 'gateway.push.apple.com'
      key               : 'key.pem'
      passphrase        : null
      port              : 2195
      resend_on_drop    : false
      timeout           : 5000
      rejectUnauthorized: true

    _.extend @options, options

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
          rejectUnauthorized: @options.rejectUnauthorized
          socket            : new net.Stream()

        @socket = tls.connect @options.port, @options.gateway, socket_options, =>
          resolve()
          delete @connect_promise
          @emit("connect#connected")
          @watchForStaleSocket()

        @socket.on "data", (data) => @socketData(data)

        # @socket.setKeepAlive(true)
        # @socket.setTimeout(@options.timeout, => console.log('timeout!'))

        @socket.setNoDelay(false)
        @socket.socket.connect @options.port, @options.gateway

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

  disconnect: (options = {}) ->
    @emit("disconnect#start")

    delete @bad_alert_sent
    delete @bytes_read
    delete @bytes_written
    delete @connect_promise

    @socket.destroy()
    delete @socket

    if options.drop
      @emit("disconnect#drop", @not_sure_if_sent)

      resend = (
        @options.resend_on_drop &&
        @not_sure_if_sent &&
        @not_sure_if_sent.length
      )

      if resend
        resend = @not_sure_if_sent.slice()
        @not_sure_if_sent = []

        @emit("disconnect#drop#resend", resend)
        @send(item) for item in resend
      else
        @emit("disconnect#drop#nothing_to_resend")
        @emit("finish")
    else
      @emit("disconnect#finish")
      @emit("finish")
      @not_sure_if_sent = []

    clearInterval(@interval) if @interval

  send: (notification) ->
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
        notification._uid = @current_id++
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

    if data[0] == 8
      @emit('socketData#invalid_token', data)

      error_code = data[1]
      identifier = data.readUInt32BE(2)

      notification = _.find @not_sure_if_sent, (item, i) =>
        item._uid == identifier
      
      if notification
        if notification.alert == 'x'
          @emit('socketData#invalid_token#intentional_bad_notification')
          @emit('done')  
        else
          @emit('socketData#invalid_token#notification', notification)
          @emit('error', notification)

          resend = @not_sure_if_sent.slice(
            @not_sure_if_sent.indexOf(notification) + 1
          )

          @disconnect()
          @emit('socketData#resend', resend)
          @send(item) for item in resend

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
          if @bad_alert_sent
            @emit('watchForStaleSocket#stale#no_response')
            @disconnect(drop: true)
          else
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