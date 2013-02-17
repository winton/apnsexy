for key, value of require('./common')
  eval("var #{key} = value;")

module.exports = class Debug extends EventEmitter

  constructor: (instance) ->
    @events   = []
    @instance = instance

    @instance.debug        = @debug
    @instance.debug_events = @events

  debug: (e, params...) =>
    @events.push(e)  unless @events.indexOf(e) > -1

    return  if @instance.options.debug_ignore.indexOf(e) > -1

    if params instanceof Array
      params = _.map(
        params
        (param) => @extractInfo(param)
      )
      params.unshift(e)
      params = _.compact(params)
    else
      _.each(
        params
        (value, key) => params[key] = @extractInfo(value)
      )
      params = [ e, params ]

    @instance.emit.apply(@instance, params)

    params.unshift('debug')
    @instance.emit.apply(@instance, params)

  extractInfo: (param) ->
    return  unless param?
    if param.alert
      alert : param.alert
      device: param.device
      uid   : param._uid
    else if param instanceof Error
      param
    else if typeof(param) == 'number'
      param + ''