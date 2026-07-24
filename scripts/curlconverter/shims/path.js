// Stub: path operations for JavaScriptCore (nunjucks init calls path.normalize)
module.exports = {
  join: function () { return Array.prototype.slice.call(arguments).join("/"); },
  resolve: function () { return Array.prototype.slice.call(arguments).join("/"); },
  dirname: function (p) { return p.replace(/\/[^/]*$/, ""); },
  basename: function (p) { var parts = p.split("/"); return parts[parts.length - 1]; },
  extname: function (p) { var m = p.match(/(\.[^.]+)$/); return m ? m[1] : ""; },
  normalize: function (p) { return p; },
  sep: "/",
};
