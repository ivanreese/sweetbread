child_process = require "child_process"
chokidar = require "chokidar"
coffeescript = require "coffeescript"
civetCompiler = require "@danielx/civet"
fs = require "fs"
globSync = require("glob").sync
PleaseReload = require "please-reload"
swc = require "@swc/core"

# Helpers
global.join = (parts, sep = "\n")-> parts.join sep
global.toArray = (input)-> [].concat(input).flat Infinity
global.toSorted = (arr)-> arr.toSorted()
global.unique = (arr)-> Array.from new Set arr
global.exec = (cmd, opts = {stdio: "inherit"})-> child_process.exec cmd, opts
global.execSync = (cmd, opts = {stdio: "inherit"})-> child_process.execSync cmd, opts

# Extend glob to support arrays of patterns
global.glob = (...patterns)-> toSorted unique toArray(patterns).flatMap (pattern)-> globSync pattern

# A tiny DSL for string replacement
global.replace = (str, kvs)->
  str = str.replace k, v for k, v of kvs
  str

# Files
global.exists = (path)-> fs.existsSync path
global.mkdir = (path)-> fs.mkdirSync path, recursive: true
global.ensureDir = (path)-> mkdir(path.split("/")[0...-1].join("/") || "."); path
global.read = (path)-> if exists path then fs.readFileSync(path).toString()
global.rm = (pattern)-> fs.rmSync path, recursive: true for path in glob pattern
global.copy = (path, dest)-> fs.copyFileSync path, ensureDir dest
global.write = (dest, text)-> fs.writeFileSync ensureDir(dest), text

# Higher level file helpers
global.readAll = (...patterns)-> glob(patterns).map(read)
global.concat = (...files)-> join toArray(files), "\n\n"

# Server
global.serve = PleaseReload.serve
global.reload = PleaseReload.reload

# Colors
do ()->
  global.white = (t)-> t
  for color, n of red: "31", green: "32", yellow: "33", blue: "34", magenta: "35", cyan: "36"
    do (color, n)-> global[color] = (t)-> "\x1b[#{n}m" + t + "\x1b[0m"

# Print msg with a timestamp
global.log = (msg)-> console.log yellow(new Date().toLocaleTimeString "en-US", hour12: false) + blue(" → ") + msg

# Log-able time since start
global.duration = (start, color = blue)-> color "(#{Math.round(10 * (performance.now() - start)) / 10}ms)"

# Errors push a notification and beep
global.err = (title, msg)->
  exec "osascript -e 'display notification \"Error\" with title \"#{title}\"'"
  exec "osascript -e beep"
  log msg

# Watch paths, and run actions whenever those paths are touched
global.watch = (paths, ...actions)->
  dotfiles = /(^|[\/\\])\../
  timeout = null
  run = ()->
    for action in actions
      if action instanceof Function then action() else invoke action
  chokidar.watch paths, ignored: dotfiles, ignoreInitial: true
  .on "error", ()-> err "Watch #{JSON.stringify paths}", red "Watching #{JSON.stringify paths} failed."
  .on "all", ()->
    clearTimeout timeout
    timeout = setTimeout run, 10

# Wrap some timing, error handling, and logging around other work
global.compile = (type, ...patterns, process)->
  try
    start = performance.now()
    if patterns.length
      files = glob patterns
      process file for file in files # Note: process should do side-effects, like writing results to disk
      log join ["Compiled", type, magenta("(#{files.length})"), duration(start)], " "
    else
      process()
      log join ["Compiled", type, duration(start)], " "
  catch msg
    err type, msg

# CODE -> CODE
global.civet = (code)-> civetCompiler.compile code, sync: true, js: true
global.coffee = (code)-> coffeescript.compile code, bare: true, inlineMap: true
global.minify = (js)-> swc.transformSync(js, minify: true, jsc: minify: compress: true, mangle: true).code

# PATH -> CODE
global.typescript = (path)-> swc.transformSync(read(path), filename: path, jsc: target: "esnext").code
