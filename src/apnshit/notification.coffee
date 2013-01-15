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

  length: ->
    Buffer.byteLength(JSON.stringify(@), @encoding || 'utf8')

  toJSON: ->
    @payload = {}  if @payload is `undefined`
    @payload.aps = {}  if @payload.aps is `undefined`
    @payload.aps.badge = @badge  if typeof @badge is "number"
    @payload.aps.sound = @sound  if typeof @sound is "string"
    @payload.aps.alert = @alert  if typeof @alert is "string" or typeof @alert is "object"
    @payload.aps["content-available"] = 1  if @newsstandAvailable
    @payload