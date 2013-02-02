module.exports = class Notification
  constructor: ->
    @alert              = undefined
    @badge              = undefined
    @device             = undefined
    @encoding           = 'utf8'
    @expiry             = 0
    @identifier         = 0
    @newsstandAvailable = undefined
    @payload            = {}
    @sound              = undefined

  data: ->
    data           = undefined
    message        = JSON.stringify(@)
    message_length = Buffer.byteLength(message, @encoding)
    position       = 0
    token          = new Buffer(@device.replace(/\s/g, ""), "hex")

    data = new Buffer(1 + 4 + 4 + 2 + token.length + 2 + message_length)
    data[position] = 1
    position++
    data.writeUInt32BE @_uid, position
    position += 4
    data.writeUInt32BE @expiry, position
    position += 4

    data.writeUInt16BE token.length, position
    position += 2
    position += token.copy(data, position, 0)
    
    data.writeUInt16BE message_length, position
    position += 2
    position += data.write(message, position, @encoding)

    data

  length: ->
    Buffer.byteLength(JSON.stringify(@), @encoding || 'utf8')

  toJSON: ->
    @payload ||= {}
    @payload.aps ||= {}
    @payload.aps.badge = @badge  if @badge?
    @payload.aps.sound = @sound  if @sound?
    @payload.aps.alert = @alert  if @alert?
    @payload.aps["content-available"] = 1  if @newsstandAvailable
    @payload