for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

module.exports = class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @buffer       = []
    @current_id   = 0
    @Notification = require './apnshit/notification'
    
    @options =
      cert              : 'cert.pem',
      key               : 'key.pem',
      ca                : null,
      passphrase        : null,
      gateway           : 'gateway.push.apple.com',
      port              : 2195,
      rejectUnauthorized: true,
      enhanced          : true,
      errorCallback     : undefined,
      cacheLength       : 100,
      autoAdjustCache   : true,
      connectionTimeout : 0

    _.extend @options, options

  connect: ->
    @defer (resolve, reject) =>
      if @socket && @socket.writable
        resolve()
      else
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.rejectUnauthorized
          socket            : new net.Stream()

        @socket = tls.connect @options.port, @options.gateway, socket_options, =>
          @emit("connect")
          resolve()
        
        @socket.setNoDelay false
        @socket.setTimeout @options.connectionTimeout
        
        @socket.on "error",       => @socketError
        @socket.on "timeout",     => @socketTimeout
        @socket.on "data", (data) => @socketData(data)
        @socket.on "drain",       => @socketDrain
        @socket.on "clientError", => @socketClientError
        @socket.on "close",       => @socketClose
        
        @socket.socket.connect @options.port, @options.gateway

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

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

        if @socketUnavailable()
          @buffer.push(notification)
          return

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

        @socket.write(data)
        @socketDrain()
    ).done()

  socketData: (data) ->
    if data[0] == 8
      error_code = data[1]
      identifier = data.readUInt32BE(2)
      console.log("notification failed:", identifier)

  socketDrain: ->
    return if @socketUnavailable()
    @send(@buffer.shift())  if @buffer.length
  
  socketError: ->
    delete @socket

  socketClientError: ->
    delete @socket
  
  socketClose: ->
    delete @socket
    @send(@buffer.shift())  if @buffer.length
  
  socketTimeout: ->
    delete @socket

  socketUnavailable: ->
    !@socket || @socket.socket.bufferSize isnt 0 || !@socket.writable