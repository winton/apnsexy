for key, value of require('./common')
  eval("var #{key} = value;")

Debug = require './debug'

module.exports = class Feedback extends EventEmitter
  
  constructor: (options) ->

    @options = _.extend(
      address     : "feedback.push.apple.com"
      ca          : null
      cert        : null
      debug       : false
      debug_ignore: []
      interval    : 60
      key         : options.cert
      librato     : null
      passphrase  : null
      port        : 2196
      secure_cert : true
      
      options
    )

    # EventEmitter requires something bound to error event
    @on('error', ->)

    new Debug(@)
    @options.librato.bindFeedback(@)  if @options.librato

    @connect().then(=> @startInterval())

  connect: ->
    @debug('connect#start', @connect_promise)

    @connect_promise ||= defer (resolve, reject) =>
      if @socket? && @socket.writable
        @debug('connect#exists')
        resolve()
      else
        @debug('connect#connecting')
        @connecting = true
        
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.secure_cert
          socket            : new net.Stream()

        @socket = tls.connect(
          @options.port
          @options.address
          socket_options
          =>
            @debug("connect#connected")
            resolve()
            delete @connect_promise
        )

        @read_buffer = new Buffer(0)

        @socket.on "data", (data) => @socketData(data)
        @socket.on "error",   (e) =>
          @debug("socket#error", e)
          @disconnect(drop: true)

  disconnect: (options = {}) ->
    @debug("disconnect#start", options)

    delete @connect_promise

    @socket.destroy()
    delete @socket

    clearInterval(@interval) if @interval?

    if options.drop
      @debug("disconnect#drop")
      @connect().then(=> @startInterval())
    else
      @debug("disconnect#finish")
      @emit("finish")

  socketData: (data) ->
    @debug('socketData#start', data)

    time         = 0
    token_length = 0
    token        = null

    @debug('socketData#received_packet', data)
    
    new_buffer = new Buffer(@read_buffer.length + data.length)
    @read_buffer.copy(new_buffer)
    data.copy(new_buffer, @read_buffer.length)

    @read_buffer = new_buffer

    while @read_buffer.length > 6
      time         = @read_buffer.readUInt32BE(0)
      token_length = @read_buffer.readUInt16BE(4)

      return if (@read_buffer.length - 6) < token_length
      
      token = new Buffer(token_length)
      @read_buffer.copy token, 0, 6, 6 + token_length

      token = token.toString("hex")

      @debug('socketData#parsed_token', time, token)
      @emit('feedback', time, token)

      @read_buffer = @read_buffer.slice(6 + token_length)

  startInterval: =>
    @debug('startInterval#start')

    clearInterval(@interval)  if @interval?
    @interval = setInterval(
      =>
        @debug('startInterval#interval_start')

        if @socket? && !@socket.writable
          @disconnect(drop: true)

      @options.interval * 1000
    )