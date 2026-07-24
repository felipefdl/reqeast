// Stub: EventEmitter for nunjucks (used by curlconverter generators, not toJsonString)
function EventEmitter() {}
EventEmitter.prototype.on = function () { return this; };
EventEmitter.prototype.emit = function () { return false; };
EventEmitter.prototype.removeListener = function () { return this; };
EventEmitter.prototype.addListener = function () { return this; };
EventEmitter.prototype.once = function () { return this; };
module.exports = EventEmitter;
module.exports.EventEmitter = EventEmitter;
