chokidar = require "chokidar"
coffeescript = require "coffeescript"
civet = require "@danielx/civet"
fs = require "fs"
globSync = require("glob").sync
PleaseReload = require "please-reload"
swc = require "@swc/core"
{exec} = require "child_process"

# Helpers
toArray = (input)-> [].concat input
unique = (arr)-> Array.from new Set arr

# Extend glob to support arrays of patterns
global.glob = (patterns)-> unique toArray(patterns).flatMap (pattern)-> globSync pattern

# Files
global.exists = (path)-> fs.existsSync path
global.mkdir = (path)-> fs.mkdirSync path, recursive: true
global.ensureDir = (path)-> mkdir(path.split("/")[0...-1].join("/")); path
global.read = (path)-> if exists path then fs.readFileSync(path).toString()
global.rm = (pattern)-> fs.rmSync path, recursive: true for path in glob pattern
global.copy = (path, dest)-> fs.copyFileSync path, ensureDir dest
global.write = (path, text)-> fs.writeFileSync ensureDir(path), text

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

# Loggable time since start
global.duration = (start, color = blue)-> color "(#{Math.round(10 * (performance.now() - start)) / 10}ms)"

# Log duration when tasks finish
global.announce = (start, count, type, dest)->
  suffix = if count is 1 then "" else "s"
  log "Compiled #{count} #{type} file#{suffix} to #{dest} " + duration start

# Errors should show a notification and beep
global.err = (title, msg)->
  exec "osascript -e 'display notification \"Error\" with title \"#{title}\"'"
  exec "osascript -e beep"
  log msg
  false # signal that something failed

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



global.Compilers = {}

Compilers.civet = (pattern, src, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = glob pattern
  for path in paths
    result = civet.compile read(path), sync: true, js: true # TODO: handle errors
    if opts.minify
      result = swc.transformSync(result, minify: true, jsc: minify: compress: true, mangle: true).code # TODO: handle errors
    write path.replace(src, dest).replace(".civet", ".js").replace(".ts", ".js"), result
  announce start, paths.length, "civet", dest unless opts.quiet
  true

Compilers.coffee = (pattern, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = glob pattern
  for path in paths
    try
      result = coffeescript.compile path, bare: true, inlineMap: !opts.minify
      if opts.minify
        result = swc.transformSync(result, minify: true, jsc: minify: compress: true, mangle: true).code # TODO: handle errors
      fs.writeFileSync dest, result
    catch err
      [msg, mistake, pointer] = err.toString().split "\n"
      [_, msg] = msg.split ": error: "
      num = err.location.first_line + " "
      pointer = pointer.padStart pointer.length + num.length
      return err "CoffeeScript", [red(paths[i]) + blue(" → ") + msg, "", blue(num) + mistake, pointer].join "\n"
  announce start, paths.length, "coffee", dest unless opts.quiet
  true

Compilers.copy = (pattern, src, dest, opts = {quiet: false})->
  start = performance.now()
  paths = glob pattern
  copy path, path.replace src, dest for path in paths
  announce start, paths.length, "static", dest unless opts.quiet
  true

Compilers.typescript = (pattern, src, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = glob pattern
  for path in paths
    result = swc.transformSync(read(path), filename: path, jsc: target: "esnext").code # TODO: handle errors
    if opts.minify
      result = swc.transformSync(result, minify: true, jsc: minify: compress: true, mangle: true).code # TODO: handle errors
    write path.replace(src, dest).replace(".ts", ".js"), result
  announce start, paths.length, "typescript", dest unless opts.quiet
  true
