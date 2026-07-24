// Stub: util.inspect and util.format for yargs error messages
module.exports = {
  inspect: function (obj) { return JSON.stringify(obj); },
  format: function () {
    var args = Array.prototype.slice.call(arguments);
    var fmt = args.shift();
    if (typeof fmt !== "string") return args.map(function (a) { return JSON.stringify(a); }).join(" ");
    return fmt.replace(/%[sdj%]/g, function (m) {
      if (m === "%%") return "%";
      if (args.length === 0) return m;
      var val = args.shift();
      if (m === "%s") return String(val);
      if (m === "%d") return Number(val);
      if (m === "%j") return JSON.stringify(val);
      return String(val);
    });
  },
};
