import showdown from 'showdown'
riot.tag('markdown', '<div></div>', function (opts) {
  this.set = () => { this.root.childNodes[0].innerHTML = convert(opts.content)}
  this.on('update', this.set)
  this.on('mount', this.set)
})

var convert = (markdown) => {
  var converter = new showdown.Converter()
  return converter.makeHtml(markdown)
}
