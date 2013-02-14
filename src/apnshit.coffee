for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

Debug        = require './apnshit/debug'
Feedback     = require './apnshit/feedback'
Librato      = require './apnshit/librato'
Notification = require './apnshit/notification'

class Apnshit extends EventEmitter
  
  constructor: (options) ->

    @options = _.extend(
      ca          : null
      cert        : 'cert.pem'
      debug       : false
      debug_ignore: []
      gateway     : 'gateway.push.apple.com'
      key         : 'key.pem'
      librato     : null
      passphrase  : null
      port        : 2195
      secure_cert : true
      timeout     : 2000
      
      options
    )

    # EventEmitter requires something bound to error event
    @on('error', ->)

    new Debug(@)    if @options.debug
    new Librato(@)  if @options.librato

    @resetVars()
    @keepSending()

  checkForStaleConnection: ->
    @debug('checkForStaleConnection#start')

    @stale_count ||= 0

    if !@stale_index? || @stale_index < @sent_index
      @stale_index = @sent_index
      @stale_count = 0

    @stale_count++  if @stale_index == @sent_index

    if @stale_count >= 2
      clearInterval(@stale_connection_timer)

      @potential_drops += @notifications.length - 1 - @sent_index
      @debug('checkForStaleConnection#@potential_drops', @potential_drops)

      total_sent      = @sent_index + 1
      potential_drops = @potential_drops

      @killSocket()
      @resetVars()

      @debug('checkForStaleConnection#stale')
      @emit('finish', total_sent, potential_drops)

  connect: ->
    @debug('connect#start')

    if !@connecting && (!@socket || !@socket.writable)
      delete @connect_promise
      delete @sent_index
      @connect_index = @index - 1

    @connect_promise ||= defer (resolve, reject) =>
      if @socket && @socket.writable
        @debug('connect#exists')
        resolve()
      else
        @debug('connect#connecting')
        @resetVars(connecting: true)

        @connecting    = true
        
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.secure_cert
          socket            : new net.Stream()
    
        setTimeout(
          =>
            @socket = tls.connect(
              @options.port
              @options.gateway
              socket_options
              =>
                @debug("connect#connected")
                @connecting = false
                resolve()
            )

            @socket.on "close",        => @socketError()
            @socket.on "data" , (data) => @socketData(data)
            @socket.on "error", (e)    => @socketError(e)

            @socket.setNoDelay(false)
            @socket.socket.connect(
              @options.port
              @options.gateway
            )
          10
        )

  enqueue: (notification) ->
    @debug("enqueue", notification)

    @uid = 0  if @uid > 0xffffffff
    notification._uid = @uid++
    
    @notifications.push(notification)

    @stale_connection_timer ||= setInterval(
      => @checkForStaleConnection()
      @options.timeout
    )

  keepSending: ->
    process.nextTick(
      =>
        @debug("keepSending")
        
        if @error_index?
          @index = @error_index + 1
          delete @error_index

        if @index != @notifications.length
          @send()

        @keepSending()
    )

  killSocket: ->
    delete @connecting
    @socket.removeAllListeners()
    @socket.writable = false

  resetVars: (options = {})->
    unless options.connecting?
      delete @connecting
      delete @error_index
      delete @stale_connection_timer

      @index           = 0
      @potential_drops = 0
      @notifications   = []
      @sent_index      = 0
      @uid             = 0

    delete @stale_count
    delete @stale_index

  send: ->
    notification = @notifications[@index]

    if notification
      @debug('send#@index', @index)

      index = @index
      @index++

      @debug("send#start", notification)
      
      @connect().then(
        =>
          @debug("send#write", notification)
          
          if @socket.writable
            @socket.write(
              notification.data()
              notification.encoding
              =>
                @sent_index = index

                @debug("send#written", notification)
                @emit("sent", notification)
            )
      )

  socketData: (data) ->
    error_code = data[0]
    identifier = data.readUInt32BE(2)

    @debug(
      'socketData#start'
      error_code: error_code
      identifier: identifier
    )

    delete @error_index

    _.each @notifications, (item, i) =>
      if item._uid == identifier
        @error_index = i
    
    if @error_index?
      @debug('socketData#@error_index', @error_index)
      notification = @notifications[@error_index]
      
      @debug('socketData#found_notification', identifier, notification)
      @emit('error', notification)  if error_code == 8

      @killSocket()

  socketError: (e) ->
    @debug('socketError#start', e)

    unless @error_index?
      @error_index = @sent_index
      @debug('socketError#@error_index', @error_index)

      @potential_drops += @error_index - @connect_index + 1
      @debug('socketError#@connect_index', @connect_index)
      @debug('socketError#@potential_drops', @potential_drops)

    @killSocket()

module.exports = 
  Apnshit     : Apnshit
  Feedback    : Feedback
  Notification: Notification
