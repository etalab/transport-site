# DSFR - escape hatch

## Objectif

Pouvoir commencer à utiliser le DSFR tout en maintenant les écrans
utilisant la CSS de template.data.gouv.fr.

## Implémentation

Dans la configuration webpack, avec le plugin [postcss-prefix-selector]:

```javascript
const prefixer = require('postcss-prefix-selector')

// css to be processed
const css = fs.readFileSync("input.css", "utf8")

// classe ".old-ds" pour pouvoir utiliser librement cette CSS
const out = postcss().use(prefixer({
prefix: '.old-ds >',
})).process(css).css;

// attribut data-disabled pour débrayer la CSS si nécessaire
const out_escape_hatch = postcss().use(prefixer({
prefix: '.old-ds :not([data-disabled])',
})).process(css).css;
```

## Prototype

```html
<html>
  <body>
    <div class="old-ds">
      <h1>should be blue</h1>
      <div><h1>should be blue</h1></div>

      <div data-disabled>
        <h1>should be white</h1>
      </div>
    </div>
    <h1>should be white</h1>
  </body>
</html>
```

```css
.old-ds > h1 {
  color: blue;
}

.old-ds :not([data-disabled]) h1 {
  color: blue;
}

body {
  background: black;
  color: white;
}
```

[postcss-prefix-selector]: https://www.npmjs.com/package/postcss-prefix-selector
