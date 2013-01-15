for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

module.exports = class Apnshit extends EventEmitter
  
  constructor: (options) ->
    @current_id   = 0
    @Notification = require './apnshit/notification'

    @options = {
      cert              : 'cert.pem',
      certData          : null,
      key               : 'key.pem',
      keyData           : null,
      ca                : null,
      pfx               : null,
      pfxData           : null,
      passphrase        : null,
      gateway           : 'gateway.push.apple.com',
      port              : 2195,
      rejectUnauthorized: true,
      enhanced          : true,
      errorCallback     : undefined,
      cacheLength       : 100,
      autoAdjustCache   : true,
      connectionTimeout : 0
    }
    _.extend @options, options

  connect: ->
    @loadKeys().then(
      =>
        options = {}

        if @pfxData
          options.pfx  = @pfxData
        else
          options.key  = @keyData
          options.cert = @certData
          options.ca   = @options.ca
        
        options.passphrase         = @options.passphrase
        options.rejectUnauthorized = @options.rejectUnauthorized
        options.socket             = new net.Stream()
        
        @socketConnect(options)
    )

  defer: (fn) ->
    d = Q.defer()
    fn(d.resolve, d.reject)
    d.promise

  loadKeys: ->
    @defer (resolve, reject) =>
      if @options.pfx? or @options.pfxData?
        if @options.pfxData
          @pfxData = @options.pfxData
          resolve()
        else
          fs.readFile @options.pfx, (err, data) =>
            if err
              reject(err)
            else
              @pfxData = data
              resolve()
      else
        if @options.certData
          @certData = @options.certData
          resolve()
        else
          fs.readFile @options.cert, (err, data) =>
            if err
              reject(err)
            else
              @certData = data.toString()
              resolve()
        if @options.keyData
          @keyData = @options.keyData
          resolve()
        else
          fs.readFile @options.key, (err, data) =>
            if err
              reject(err)
            else
              @keyData = data.toString()
              resolve()

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

        @socket.write(data)
    ).done()

  socketConnect: (options) ->
    @defer (resolve, reject) =>
      @socket = tls.connect @options.port, @options.gateway, options, =>
        @emit("connect")
        resolve()
      
      @socket.setNoDelay false
      @socket.setTimeout @options.connectionTimeout
      
      @socket.on "error", @socketError
      @socket.on "timeout", @socketTimeout
      @socket.on "data", @socketData
      @socket.on "drain", @socketDrain
      @socket.on "clientError", @socketClientError
      @socket.on "close", @socketClose
      
      @socket.socket.connect @options.port, @options.gateway

  socketData: ->
    console.log("socket data")

  socketDrain: ->
    console.log("socket drain")
  
  socketError: ->
    console.log("socket error")

  socketClientError: ->
    console.log("socket client error")
  
  socketClose: ->
    console.log("socket close")
  
  socketTimeout: ->
    console.log("socket timeout")