for key, value of require('./common')
  eval("var #{key} = value;")

Metrics = require('librato-metrics')

module.exports = class Librato extends EventEmitter
  constructor: (options) ->
    @metrics = Metrics.createClient(options)

    @resetVars()

    setInterval(
      =>
        gauges = {}

        if @drops == 0 && @errors == 0 && @sent == 0 && @successes == 0
          @emit('finish')

        gauges.errors     = value: @errors
        gauges.total_sent = value: @sent

        @resetVars()

        @gauges(
          gauges
        ).fail(
          (e) => throw e
        ).fin(
          => @resetVars()
        )
      10 * 1000
    )

  bind: (instance) ->
    instance.on('finish', @finish)
    instance.on('error' , => @errors++)
    instance.on('sent'  , => @sent++)

  counters: (counters) ->
    @post(counters: counters)

  finish: (counts) =>
    @drops     = counts.potential_drops
    @successes = counts.total_sent

    @gauges(
      drop_pct       : value: @drops / counts.total_notifications
      error_pct      : value: counts.total_errors / counts.total_notifications
      potential_drops: value: @drops
      successes      : value: @successes
    ).fail(
      (e) => throw e
    )

  gauges: (gauges) ->
    @post(gauges: gauges)

  post: (data) ->
    defer (resolve, reject) =>
      @metrics.post(
        '/metrics'
        data
        (err, response) ->
          if err
            reject(err)
          else
            resolve(response)
      )

  resetVars: ->
    @drops     = 0
    @errors    = 0
    @sent      = 0
    @successes = 0