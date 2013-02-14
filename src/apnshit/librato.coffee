for key, value of require('./common')
  eval("var #{key} = value;")

Metrics = require('librato-metrics')

module.exports = class Librato
  constructor: (instance) ->
    @metrics = Metrics.createClient(instance.options.librato)
    @errors  = 0

    instance.on(
      'finish'
      (alerts_sent, potential_drops) =>
        drop_pct  = potential_drops / alerts_sent
        error_pct = @errors         / alerts_sent

        @post(
          gauges:
            alerts_sent:
              value: alerts_sent
            drop_pct:
              value: drop_pct
            error_pct:
              value: error_pct
            errors:
              value: @errors
            potential_drops:
              value: potential_drops
          counters:
            total_alerts_sent:
              value: alerts_sent
        ).fail(
          (e) => throw e
        ).fin(
          => @errors = 0
        )
    )

    instance.on('error', => @errors++)

  counters: (counters...) ->
    @post(counters: counters)

  gauges: (gauges...) ->
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