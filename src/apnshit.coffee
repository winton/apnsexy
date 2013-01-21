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
    console.log('connect @connect_promise', @connect_promise)
    @connect_promise ||= @defer (resolve, reject) =>
      if @socket && @socket.writable
        console.log('connection exists')
        resolve()
      else
        console.log('connecting!')
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
          @emit("connect")
          @watchForStaleSocket()
          console.log('connected!')

        @socket.on "end",         => @socketEnd
        @socket.on "error",       => @socketError
        @socket.on "timeout",     => @socketTimeout
        @socket.on "data", (data) => @socketData(data)
        @socket.on "drain",       => @socketDrain
        @socket.on "clientError", => @socketClientError
        @socket.on "close",       => @socketClose

        # @socket.setKeepAlive(true)
        @socket.setNoDelay(false)
        # @socket.setTimeout(@options.timeout, => console.log('timeout!'))
        @socket.socket.connect @options.port, @options.gateway

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

  disconnect: (options = {}) ->
    console.log('disconnect')

    delete @bad_alert_sent
    delete @bytes_read
    delete @bytes_written
    delete @connect_promise

    @socket.destroy()
    delete @socket

    if options.drop
      drop = (
        @options.resend_on_drop &&
        @not_sure_if_sent &&
        @not_sure_if_sent.length
      )
      console.log(
        "drop @not_sure_if_sent.length"
        if @not_sure_if_sent.length then @not_sure_if_sent.length else 0
      )
      if drop
        resend = @not_sure_if_sent.slice()
        @not_sure_if_sent = []
        
        console.log('drop resend', @inspect(resend))
        console.log('drop resend.length', resend.length)

        for item in resend
          @send(item)
      else
        @emit('done')
    else
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
          console.log('write', notification.alert)
          @socket.write data, encoding, =>
            resolve(notification)
    )

  socketData: (data) ->
    console.log('socketData', data[0])
    if data[0] == 8
      error_code = data[1]
      identifier = data.readUInt32BE(2)

      notification = _.find @not_sure_if_sent, (item, i) =>
        item._uid == identifier
      
      if notification
        if notification.alert == 'x'
          @emit('done')  
        else
          console.log('error', notification.alert)
          @emit('error', notification)

          resend = @not_sure_if_sent.slice(
            @not_sure_if_sent.indexOf(notification) + 1
          )

          @disconnect(drop: @bad_alert_sent)

          console.log('resend', @inspect(resend))
          console.log('resend.length', resend.length)
          
          for item in resend
            # console.log('resend', item.alert)
            @send(item)

  inspect: (arr) ->
    output = _.map arr, (item) -> item.alert
    "[ #{output.join(',')} ]"

  socketDrain: ->
    console.log('socket drain')
  
  socketEnd: ->
    console.log('socket end')
    @disconnect()

  socketError: ->
    console.log('socket error')
    @disconnect()

  socketClientError: ->
    console.log('socket client error')
    @disconnect()
  
  socketClose: ->
    console.log('socket close')
    @disconnect()
  
  socketTimeout: ->
    console.log('socket timeout')
    @disconnect()

  watchForStaleSocket: =>
    console.log('watchForStaleSocket')

    clearInterval(@interval) if @interval
    @interval = setInterval(
      =>
        console.log('setInterval')
        console.log('socket?', if @socket then 'true' else 'false')
        console.log("@socket.writable", @socket.writable) if @socket

        if @socket && !@socket.writable
          @disconnect(drop: true)
          return

        return unless @socket && @socket.writable

        stale = (
          @socket.bytesRead    == @bytes_read &&
          @socket.bytesWritten == @bytes_written
        )

        console.log("stale", stale)

        if stale
          if @bad_alert_sent
            console.log("bad alert not responded to")
            @disconnect(drop: true)
          else
            console.log("sending bad alert!")

            noti = new @Notification()
            noti.alert  = "x"
            noti.badge  = 0
            noti.sound  = 'default'
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