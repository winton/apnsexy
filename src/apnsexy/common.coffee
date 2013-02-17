common =
  EventEmitter: require('events').EventEmitter
  fs: require('fs')
  net: require('net')
  Q: require('q')
  tls: require('tls')
  _: require('underscore')

common.defer = (fn) ->
  d = common.Q.defer()
  fn(d.resolve, d.reject)
  d.promise

module.exports = common