for key, value of require('./common')
  eval("var #{key} = value;")

module.exports = class Feedback extends EventEmitter
  
  constructor: (options) ->
    @on "error", ->

    @options =
      address     : "feedback.push.apple.com"
      ca          : null
      cert        : "cert.pem"
      debug       : false
      debug_ignore: []
      interval    : 60
      key         : "key.pem"
      passphrase  : null
      port        : 2196
      secure_cert : true

    _.extend @options, options

    if @options.debug
      _.each @events, (e) =>
        @on e, (a, b) =>
          return if @options.debug_ignore.indexOf(e) >= 0
          @emit('debug', e)

    @connect().then(=> @startInterval())

  connect: ->
    @emit('connect#start', @connect_promise)

    @connect_promise ||= defer (resolve, reject) =>
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
          rejectUnauthorized: @options.secure_cert

        @socket = tls.connect(
          @options.port
          @options.address
          socket_options
          =>
            @emit("connect#connected")
            resolve()
            delete @connect_promise
        )

        @read_buffer = new Buffer(0)

        @socket.on "data", (data) => @socketData(data)
        @socket.on "error",   (e) =>
          @emit("socket#error", e)
          @disconnect(drop: true)

  events: [
    'connect#start'
    'connect#exists'
    'connect#connecting'
    'connect#connected'
    'disconnect#start'
    'disconnect#drop'
    'disconnect#finish'
    'socket#error'
    'socketData#start'
    'socketData#received_packet'
    'socketData#parsed_token'
    'startInterval#start'
    'startInterval#interval_start'
  ]

  disconnect: (options = {}) ->
    @emit("disconnect#start", options)

    delete @connect_promise

    @socket.destroy()
    delete @socket

    clearInterval(@interval) if @interval

    if options.drop
      @emit("disconnect#drop")
      @connect().then(=> @startInterval())
    else
      @emit("disconnect#finish")
      @emit("finish")

  socketData: (data) ->
    @emit('socketData#start', data)

    time         = 0
    token_length = 0
    token        = null

    @emit('socketData#received_packet', data)
    
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

      @emit('socketData#parsed_token', time, token)
      @emit('feedback', time, token)

      @read_buffer = @read_buffer.slice(6 + token_length)

  startInterval: =>
    @emit('startInterval#start')

    clearInterval(@interval) if @interval
    @interval = setInterval(
      =>
        @emit('startInterval#interval_start')

        if @socket && !@socket.writable
          @disconnect(drop: true)

      @options.interval * 1000
    )