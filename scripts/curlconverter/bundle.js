const esbuild = require("esbuild");
const path = require("path");

esbuild
  .build({
    entryPoints: [path.join(__dirname, "entry.js")],
    bundle: true,
    minify: true,
    format: "iife",
    globalName: "CurlConverter",
    platform: "neutral",
    target: "es2020",
    mainFields: ["main", "module"],
    alias: {
      fs: path.join(__dirname, "shims/fs.js"),
      path: path.join(__dirname, "shims/path.js"),
      util: path.join(__dirname, "shims/util.js"),
      assert: path.join(__dirname, "shims/assert.js"),
      url: path.join(__dirname, "shims/url.js"),
      events: path.join(__dirname, "shims/events.js"),
      domain: path.join(__dirname, "shims/domain.js"),
    },
    outfile: path.join(__dirname, "../../Reqeast/Resources/curlconverter.bundle.js"),
  })
  .then(() => {
    console.log("curlconverter bundle created successfully");
  })
  .catch((err) => {
    console.error("Bundle failed:", err);
    process.exit(1);
  });
