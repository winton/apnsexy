for key, value of require('./apnshit/common')
  eval("var #{key} = value;")

Feedback     = require './apnshit/feedback'
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
      passphrase  : null
      port        : 2195
      secure_cert : true
      timeout     : 2000
      
      options
    )

    # EventEmitter requires something bound to error event
    @on('error', ->)

    @resetVars()
    @attachDebugEvents()
    @keepSending()

  attachDebugEvents: ->
    if @options.debug
      _.each @events, (e) =>
        @on e, (a, b) =>
          return  if @options.debug_ignore.indexOf(e) >= 0
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
          else if e == "socketData#found_notification"
            @emit('debug', e, a.device)
          else if e == "send#start"
            @emit('debug', e, a.device)
          else
            @emit('debug', e)

  checkForStaleConnection: ->
    @emit('checkForStaleConnection#start')

    @stale_index ||= @sent_index
    @stale_count ||= 0

    @stale_count++  if @stale_index == @sent_index

    if @stale_count >= 2
      clearInterval(@stale_connection_timer)
      @resetVars()
      
      @emit('checkForStaleConnection#stale')
      @emit('finish')

  connect: ->
    @emit('connect#start')

    unless @socket && @socket.writable
      delete @connect_promise

    @connect_promise ||= defer (resolve, reject) =>
      if @socket && @socket.writable
        @emit('connect#exists')
        resolve()
      else
        @emit('connect#connecting')

        @resetVars(stale_only: true)
        
        socket_options =
          ca                : @options.ca
          cert              : fs.readFileSync(@options.cert)
          key               : fs.readFileSync(@options.key)
          passphrase        : @options.passphrase
          rejectUnauthorized: @options.secure_cert
          socket            : new net.Stream()
    
        setTimeout(
          =>
            @socket = tls.connect @options.port, @options.gateway, socket_options, =>
              @emit("connect#connected")
              resolve()

            @socket.on "close",        => @socketError()
            @socket.on "data" , (data) => @socketData(data)
            @socket.on "error", (e)    => @socketError(e)

            @socket.setNoDelay(false)
            @socket.socket.connect(@options.port, @options.gateway)
          100
        )

  killSocket: ->
    @socket.removeAllListeners()
    @socket.writable = false

  enqueue: (notification) ->
    @emit("enqueue", notification)

    @uid = 0  if @uid > 0xffffffff
    notification._uid = @uid++
    
    @notifications.push(notification)

    @stale_connection_timer ||= setInterval(
      => @checkForStaleConnection(),
      Math.floor(@options.timeout)
    )

  events: [
    "checkForStaleConnection#start"
    "checkForStaleConnection#stale"
    "connect#start"
    "connect#exists"
    "connect#connecting"
    "connect#connected"
    "enqueue"
    "keepSending"
    "send#start"
    "send#write"
    "send#written"
    "socketData#start"
    "socketData#found_notification"
    "socketError#start"
  ]

  keepSending: ->
    process.nextTick(
      =>
        @emit("keepSending")
        
        if @error_index?
          @index = @error_index + 1
          delete @error_index

        if !@sending && @index != @notifications.length
          @send()
        
        @keepSending()
    )

  resetVars: (options = {})->
    unless options.stale_only?
      @index         = 0
      @notifications = []
      @sent_index    = 0
      @uid           = 0

    delete @stale_connection_timer
    delete @stale_count
    delete @stale_index

  send: ->
    notification = @notifications[@index]

    if notification
      console.log('send#@index', @index)

      index    = @index
      @sending = true

      @index++

      @emit("send#start", notification)
      
      @connect().then(
        =>
          @emit("send#write", notification)
          
          if @socket.writable
            @socket.write notification.data(), notification.encoding, =>
              @emit("send#written", notification)

              @sending    = false
              @sent_index = index
          else
            @sending = false
      )

  socketData: (data) ->
    @emit('socketData#start', data)

    error_code = data[0]
    identifier = data.readUInt32BE(2)

    delete @error_index

    _.each @notifications, (item, i) =>
      if item._uid == identifier
        @error_index = i
    
    if @error_index?
      console.log('socketData#@error_index', @error_index)
      notification = @notifications[@error_index]
      
      @emit('socketData#found_notification', notification)
      @emit('error', notification)  if error_code == 8

      @killSocket()

  socketError: (e) ->
    @emit('socketError#start', e)

    @error_index = @sent_index + 1  unless @error_index?
    console.log('socketError#@error_index', @error_index)

    @killSocket()

module.exports = 
  Apnshit     : Apnshit
  Feedback    : Feedback
  Notification: Notification