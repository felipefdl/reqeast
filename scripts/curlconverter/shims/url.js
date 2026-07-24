// curlconverter uses require('url') for URL.parse and URL.format
// Must not rely on the Web URL constructor (unavailable in JavaScriptCore)
module.exports = {
  parse: function (urlString) {
    if (!urlString) return { href: "" };

    var rest = urlString;
    var protocol = null;
    var slashes = false;
    var auth = null;
    var hostname = null;
    var host = null;
    var port = null;
    var pathname = "/";
    var search = null;
    var query = null;
    var hash = null;

    // Extract hash
    var hashIdx = rest.indexOf("#");
    if (hashIdx !== -1) {
      hash = rest.slice(hashIdx);
      rest = rest.slice(0, hashIdx);
    }

    // Extract search/query
    var searchIdx = rest.indexOf("?");
    if (searchIdx !== -1) {
      search = rest.slice(searchIdx);
      query = rest.slice(searchIdx + 1);
      rest = rest.slice(0, searchIdx);
    }

    // Extract protocol
    var protoMatch = rest.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*:)/);
    if (protoMatch) {
      protocol = protoMatch[1].toLowerCase();
      rest = rest.slice(protocol.length);
    }

    // Check for slashes
    if (rest.slice(0, 2) === "//") {
      slashes = true;
      rest = rest.slice(2);
    }

    if (slashes) {
      // Extract auth
      var atIdx = rest.indexOf("@");
      // Only treat @ as auth delimiter if it appears before the first /
      var firstSlash = rest.indexOf("/");
      if (atIdx !== -1 && (firstSlash === -1 || atIdx < firstSlash)) {
        auth = rest.slice(0, atIdx);
        rest = rest.slice(atIdx + 1);
      }

      // Extract host (hostname + port)
      var hostEnd = rest.indexOf("/");
      var hostPart = hostEnd !== -1 ? rest.slice(0, hostEnd) : rest;
      rest = hostEnd !== -1 ? rest.slice(hostEnd) : "";

      // Check for IPv6
      if (hostPart.charAt(0) === "[") {
        var bracketEnd = hostPart.indexOf("]");
        if (bracketEnd !== -1) {
          hostname = hostPart.slice(0, bracketEnd + 1);
          var afterBracket = hostPart.slice(bracketEnd + 1);
          if (afterBracket.charAt(0) === ":") {
            port = afterBracket.slice(1);
          }
        } else {
          hostname = hostPart;
        }
      } else {
        var colonIdx = hostPart.lastIndexOf(":");
        if (colonIdx !== -1) {
          var possiblePort = hostPart.slice(colonIdx + 1);
          if (/^\d+$/.test(possiblePort)) {
            hostname = hostPart.slice(0, colonIdx);
            port = possiblePort;
          } else {
            hostname = hostPart;
          }
        } else {
          hostname = hostPart;
        }
      }

      host = hostname + (port ? ":" + port : "");
      pathname = rest || "/";
    } else {
      pathname = rest || "/";
    }

    var href = (protocol || "") + (slashes ? "//" : "") + (auth ? auth + "@" : "") + (host || "") + pathname + (search || "") + (hash || "");

    return {
      protocol: protocol,
      hostname: hostname,
      host: host,
      port: port || null,
      pathname: pathname,
      search: search || null,
      query: query || null,
      hash: hash || null,
      href: href,
      path: pathname + (search || ""),
      auth: auth || null,
      slashes: slashes,
    };
  },
  format: function (obj) {
    if (typeof obj === "string") return obj;
    var protocol = obj.protocol || "";
    var slashes = obj.slashes ? "//" : "";
    var auth = obj.auth ? obj.auth + "@" : "";
    var hostname = obj.hostname || obj.host || "";
    var port = obj.port ? ":" + obj.port : "";
    var pathname = obj.pathname || "/";
    // Node.js behavior: if "search" key exists on the object, use it (null = no search).
    // Only fall back to "query" when "search" is not a property at all.
    var search;
    if ("search" in obj) {
      search = obj.search || "";
    } else if (obj.query) {
      search = "?" + (typeof obj.query === "string" ? obj.query : "");
    } else {
      search = "";
    }
    var hash = obj.hash || "";
    return protocol + slashes + auth + hostname + port + pathname + search + hash;
  },
  URL: typeof URL !== "undefined" ? URL : function () {},
};
