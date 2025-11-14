# Sweetbread

A totally vegan helper library for my Cakefiles.

## Compilers

I'm removing some of the compilers to cut down on the number of deps. To compile a language, use one of these recipes. Note that some of them take a filepath, and others take a string of source code.

#### Typescript
`npm i --save-dev @swc/core`

```coffee
swc = require "@swc/core"
typescript = (path)-> swc.transformSync(read(path), filename: path, jsc: target: "esnext").code
```

#### CoffeeScript
```coffee
coffeescript = require "coffeescript"
coffee = (code)-> coffeescript.compile code, bare: true, inlineMap: true
```

#### Civet
`npm i --save-dev @danielx/civet`

```coffee
civetCompiler = require "@danielx/civet"
civet = (code)-> civetCompiler.compile code, sync: true, js: true
```

#### Minified JS
`npm i --save-dev @swc/core`

```coffee
swc = require "@swc/core"
minify = (code)-> swc.transformSync(code, minify: true, jsc: minify: compress: true, mangle: true).code
```