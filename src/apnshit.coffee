for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

module.exports = class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @current_id       = 0
    @Notification     = require './apnshit/notification'
    @not_sure_if_sent = []

    @on "error", ->
    
    @options =
      ca                : null
      cert              : 'cert.pem'
      enhanced          : true
      gateway           : 'gateway.push.apple.com'
      key               : 'key.pem'
      passphrase        : null
      port              : 2195
      timeout           : 5000
      rejectUnauthorized: true

    _.extend @options, options

  finished: =>
    @finished ||= 0
    setTimeout(
      =>
        @finished += 1
        if @finished >= 5 || !@socket.bufferSize
          @disconnect()
          @finished = 0
          @emit('done')
        else
          @checkIfDone()
      @options.timeout
    )

  connect: ->
    if @connecting
      @connect_promise
    else
      @connect_promise = @defer (resolve, reject) =>
        if @socket && @socket.writable
          resolve()
        else
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
            @connecting = false
            @emit("connect")

          @socket.on "error",       => @socketError
          @socket.on "timeout",     => @socketTimeout
          @socket.on "data", (data) => @socketData(data)
          @socket.on "drain",       => @socketDrain
          @socket.on "clientError", => @socketClientError
          @socket.on "close",       => @socketClose

          @socket.setNoDelay(false)
          @socket.setTimeout(@options.timeout, @finished)
          @socket.socket.connect @options.port, @options.gateway

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

  disconnect: ->
    @socket.destroy()
    delete @socket

  send: (notification) ->
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
          @socket.write data, encoding, =>
            resolve(notification)
    )

  socketData: (data) ->
    if data[0] == 8
      error_code = data[1]
      identifier = data.readUInt32BE(2)

      notification = _.find @not_sure_if_sent, (item, i) =>
        item._uid == identifier
        
      if notification
        @emit('error', notification)

        resend = @not_sure_if_sent.slice(
          @not_sure_if_sent.indexOf(notification) + 1
        )

        @not_sure_if_sent = []
        @disconnect()
        
        for item in resend
          @send(item)

  inspect: (arr) ->
    output = _.map arr, (item) -> item.alert
    "[ #{output.join(',')} ]"

  socketDrain: ->
    console.log('socket drain')
  
  socketError: ->
    console.log('socket error')
    delete @socket

  socketClientError: ->
    console.log('socket client error')
    delete @socket
  
  socketClose: ->
    console.log('socket close')
    delete @socket
  
  socketTimeout: ->
    console.log('socket timeout')
    delete @socket