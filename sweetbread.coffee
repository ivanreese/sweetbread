autoprefixer = require "autoprefixer"
chokidar = require "chokidar"
CleanCSS = require "clean-css"
coffeescript = require "coffeescript"
civet = require "@danielx/civet"
fs = require "fs"
glob = require "glob"
http = require "http"
htmlmin = require "html-minifier"
kit = require "node-kit"
os = require "os"
path = require "path"
PleaseReload = require "please-reload"
postcss = require "postcss"
sass = require "sass"
swc = require "@swc/core"
ws = require "ws"
{execSync, exec} = require "child_process"


# This top section is for internal helpers.

# Make sure that the input is an array
toArray = (input)-> [].concat input

# Given a list of paths to files, get the contents of each file
readFiles = (filePaths)->
  readFile filePath for filePath in filePaths

readFile = (filePath)->
  fs.readFileSync(filePath).toString()

# Given a file type, a list of paths to files, and the contents of each file,
# return a list of contents with the filename prepended as a comment.
prependFilenames = (comment, paths, contents)->
  for filePath, i in paths
    comment.replace("%%", filePath) + "\n" + contents[i]


# The following sections are the functions you can use in your Cakefile.
# Each exposed function is placed on global, so just call them directly.


# LOGGING #########################################################################################

# Who needs chalk when you can just roll your own ANSI escape sequences
do ()->
  global.white = (t)-> t
  for color, n of red: "31", green: "32", yellow: "33", blue: "34", magenta: "35", cyan: "36"
    do (color, n)-> global[color] = (t)-> "\x1b[#{n}m" + t + "\x1b[0m"

# Handy little separator for logs
arrow = blue " → "

# Print out logs with nice-looking timestamps
global.log = (msg)->
  time = yellow new Date().toLocaleTimeString "en-US", hour12: false
  console.log time + arrow + msg
  return msg # pass through

# Generate a nice looking duration string for appending to logs
global.duration = (start, color = blue)-> color " (#{Math.round(10 * (performance.now() - start)) / 10}ms)"

# Errors should show a notification and beep
global.err = (title, msg)->
  exec "osascript -e 'display notification \"Error\" with title \"#{title}\"'"
  exec "osascript -e beep"
  log msg
  return false # signal that something failed


# FILE SYSTEM #####################################################################################

# Convenience wrapper for recursive rm
global.rm = (pattern)->
  for filePath in glob.sync pattern
    fs.rmSync filePath, recursive: true

# Convenience wrapper for recursive mkdir
global.mkdir = (filePath)->
  fs.mkdirSync filePath, recursive: true


# LIVE SERVER #####################################################################################

global.serve = (root)->
  PleaseReload.serve root

global.reload = ()->
  PleaseReload.reload()


# COMPILERS #######################################################################################

global.Compilers = {}

Compilers.civet = (paths, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = toArray paths
  contents = readFiles paths
  concatenated = prependFilenames("// %%", paths, contents).join "\n\n\n"
  result = civet.compile concatenated, js: true # TODO: No error handling
  if opts.minify
    result = swc.transformSync(result, minify: true, jsc: minify: compress: true, mangle: true).code # TODO: We don't yet handle errors during minification
  fs.writeFileSync dest, result
  log "Compiled #{dest}" + duration start unless opts.quiet
  return true # signal success

Compilers.coffee = (paths, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = toArray paths
  contents = readFiles paths
  concatenated = prependFilenames("# %%", paths, contents).join "\n\n\n"
  try
    result = coffeescript.compile concatenated, bare: true, inlineMap: !opts.minify
    if opts.minify
      result = swc.transformSync(result, minify: true, jsc: minify: compress: true, mangle: true).code # TODO: We don't yet handle errors during minification
    fs.writeFileSync dest, result
    log "Compiled #{dest}" + duration start unless opts.quiet
    return true # signal success
  catch outerError
    # We hit an error while compiling. To improve the error message, try to compile each
    # individual source file, and see if any of them hit an error. If so, log that.
    for content, i in contents
      try
        coffeescript.compile content, bare: true
      catch innerError
        [msg, mistake, pointer] = innerError.toString().split "\n"
        [_, msg] = msg.split ": error: "
        num = innerError.location.first_line + " "
        pointer = pointer.padStart pointer.length + num.length
        return err "CoffeeScript", [red(paths[i]) + arrow + msg, "", blue(num) + mistake, pointer].join "\n"
    err "CoffeeScript", outerError

htmlminOptions =
  collapseWhitespace: false # Leave this off! It can produce a visibly different result between dev and prod!
  collapseBooleanAttributes: true
  conservativeCollapse: false
  includeAutoGeneratedTags: false
  minifyCSS: true
  minifyJS: true
  removeComments: true
  sortAttributes: true
  sortClassName: true

Compilers.html = (paths, dest, opts = {minify: false, quiet: false})->
  start = performance.now()
  paths = toArray paths
  contents = readFiles paths
  contents = prependFilenames("<!-- %% -->", paths, contents) if contents.length > 1
  result = contents.join "\n\n"
  if opts.minify
    result = htmlmin.minify result, htmlminOptions
  fs.writeFileSync dest, result
  log "Compiled #{dest}" + duration start unless opts.quiet
  return true # signal success

Compilers.kit = (path, dest, opts = {minify: false, quiet: false})-> # Note — just 1 file at a time
  start = performance.now()
  result = kit path
  if opts.minify
    result = htmlmin.minify result, htmlminOptions
  fs.writeFileSync dest, result
  log "Compiled #{dest}" + duration start unless opts.quiet
  return true # signal success

defaultBrowserslist = "last 5 Chrome versions, last 5 ff versions, last 3 Safari versions, last 3 iOS versions"
Compilers.scss = (paths, dest, opts = {minify: false, quiet: false, browserslist: null})->
  start = performance.now()
  paths = toArray paths
  contents = readFiles paths
  concatenated = prependFilenames("/* %% */", paths, contents).join "\n\n"
  plugins = [autoprefixer overrideBrowserslist: toArray opts.browserslist or defaultBrowserslist]
  try
    compiled = sass.compileString(concatenated, sourceMap: false).css
    processed = postcss(plugins).process compiled
    log red warning.toString() for warning in processed.warnings()
    result = processed.css
    if opts.minify
      result = new CleanCSS().minify(result).styles
    fs.writeFileSync dest, result
    log "Compiled #{dest}" + duration start unless opts.quiet
    return true # signal success
  catch outerError
    # We hit an error while compiling. To improve the error message, we'll try to compile each
    # individual source file, and see if any of them hit an error. If so, we'll log that.
    # But this won't work if there are SCSS variables shared between files. So if you use any
    # SCSS variables at all, the best we can do is just log the original error.
    if concatenated.indexOf("$") > -1
      err "SCSS", outerError.toString()
    else
      for content, i in contents
        try
          compiled = sass.compileString(content, sourceMap: false, alertColor: false).css
        catch innerError
          err "SCSS", innerError.toString()
          # [msg, _, mistake, pointer] = innerError.toString().split "\n"
          # [num, mistake] = mistake.split " │"
          # [_, pointer] = pointer.split " │"
          # pointer = pointer.padStart(pointer.length + num.length)
          # return err "SCSS", [red(paths[i]) + arrow + msg, "", blue(num) + mistake, red(pointer)].join "\n"
    err "SCSS", outerError

Compilers.static = (path, dest, opts = {quiet: false})-> # Note — just 1 file at a time
  start = performance.now()
  fs.copyFileSync path, dest
  log "Compiled #{dest}" + duration start unless opts.quiet
  return true # signal success


# TASKS ###########################################################################################

global.doInvoke = (task)->
  log cyan task + "…"
  invoke task

# Watch paths, and run actions whenever those paths are touched
dotfiles = /(^|[\/\\])\../
global.watch = (paths, ...actions)->
  timeout = null
  run = ()->
    for action in actions
      if action instanceof Function then action() else doInvoke action
  chokidar.watch paths, ignored: dotfiles, ignoreInitial: true
  .on "error", ()-> err "Watch #{JSON.stringify paths}", red "Watching #{JSON.stringify paths} failed."
  .on "all", (event, filePath)->
    clearTimeout timeout
    timeout = setTimeout run, 10
