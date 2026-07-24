// Stub: curlconverter doesn't read files at runtime for toJsonString
module.exports = {
  readFileSync: function () { return ""; },
  readdirSync: function () { return []; },
  statSync: function () { return { isDirectory: function () { return false; } }; },
  existsSync: function () { return false; },
};
