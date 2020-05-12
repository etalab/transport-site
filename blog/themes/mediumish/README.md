# Mediumish Theme

This theme for gohugo is a customized port based on the [Mediumish Jekyll-Theme](//github.com/wowthemesnet/mediumish-theme-jekyll) by [WowThemesNet](//github.com/wowthemesnet). The original theme ships with a few more features than this ported version but i also added features which the original version did not include.

See the [Demo](https://lgaida.github.io/mediumish-gohugo-theme-demo) and [Demo-Source](https://github.com/lgaida/mediumish-gohugo-theme-demo)

![screenshot](https://raw.githubusercontent.com/lgaida/mediumish-gohugo-theme/master/images/screenshot.png)

## Features
+ Landingpage
+ 404-Page
+ Posts
    + tags can be used
    + shareable via socialmedia
+ Custom pagination
+ Prev/Next-Links
+ Tag-Overview in Jumbotron
+ Integrations:
    + Disqus Comments
    + Google Analytics
    + Mailchimp

## Installation
Inside the folder of your Hugo site run:

    $ cd themes
    $ git clone https://github.com/lgaida/mediumish-gohugo-theme

## Preface
I recommend placing image files for your site config within the `static` folder of your gohugo website. This allows them to be easily referenced from the config.toml or post.md files. You may structure the files and folders within `static` however you'd like, with one exception: There must be a file named `jumbotron.jpg` present under the path `static/images` as it is referenced in the .css.


## Post Example
To create a simple post use the hugo new command as usual.
This theme makes use of page bundles / page resource (see https://gohugo.io/content-management/page-bundles/).
Place any image next to your post's index.md file and make sure it contains the keyword "cover" inside its name.
This image will also be used for twitter and opengraph cards.

```
hugo new blog/my-first-post/index.md
```

Creating a new post will create something like this:
```
---
title: "My first post"
date: 2018-10-01T15:25:19+02:00
publishdate: 2018-10-07T11:17:14+02:00
lastmod: 2018-10-08T18:55:29+02:00
tags: ["post", "interesting"]
type: "post"
comments: false
---
# Lorem ipsum
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean semper libero quis dictum dapibus. Nulla egestas vitae augue eu rutrum. Duis ullamcorper dictum ipsum. Interdum et malesuada fames ac ante ipsum primis in faucibus. Suspendisse tortor dui, fermentum non dapibus id, volutpat non odio.
```

`publishdate`: is displayed at the top of the single-view\
`lastmod`: is displayed as a hint on the single-view\
`tags`: are used as usual, just add the tags you want to use. They are displayed in the jumbotron on the list-view, and on the bottom of each single-view\
`comments`: true/false to turn on/off disqus-comments


## Static Content
I added a customized layout for content of type "static", which means that posts in the folder "static" are displayed as standalone pages. I also disabled the list-layout for this folder.

For example: to create an imprint, simply go with the following command and add your markdown-text.
```
hugo new static/imprint.md
```

## Configuration
You should at least specify the following default params in your config.toml
```toml
baseURL = "http://yourdomain.com"
languageCode = "en-us"
title = "Mediumish"
theme = "mediumish-gohugo-theme"
summaryLength = 25
copyright = "John Doe - All rights reserved"
disqusShortname = "shortDisquis"
googleAnalytics = "UA-1XXXXXXX1-X"
```
`title`: is displayed on the postlist and on each post as the title\
`summaryLength`: feel free to play around with this\
`copyright`: is displayed in the footer next to the copyright-logo\
`disqusShortname`: provide your disqusShortname\
`googleAnalytics`: provide your googleAnalytics-Code

### General Params
```toml
[params]
  logo = "/images/icon.png"
  description ="the clean blog!"
  mailchimp = "you can provide a mailchimp-link here, see below"
  mailprotect = "you can provide a protector-name here, see below"
```
`logo`: is displayed in titlebar and alertbar\
`description`: is displayed under title\
`mailchimp` and `mailprotect`: provide links to a mailchimp-list and a mailchimp-protector id, the following screenshot should clarify. if not specified the alertbar for mail-subscription doesn't show up.

![mailchimp-example](https://raw.githubusercontent.com/lgaida/mediumish-gohugo-theme/master/images/mailchimp.png)

### Author Params
```toml
[params.author]
  name = "John Doe"
  thumbnail = "/images/author.jpg"
  description = "Creator of this blog."
```
![author-params](https://raw.githubusercontent.com/lgaida/mediumish-gohugo-theme/master/images/authorpost.png)

### Landingpage Params
```toml
[params.index]
  picture = "/images/author.jpg"
  title = "John Doe"
  subtitle = "I'm a unique placeholder. Working here and there!"
  mdtext = '''Currently trying to get this blog running, still don't know what the blog will be about!\
**This textblock is a demonstration of the mdtext-param.**\
### This is a markdown heading'''
  alertbar = true
```
You can currently provide your username from `github`, `linkedin`, `xing`, `twitter`, `medium`. They will be displayed as icons on the landingpage.
```toml
[params.social]
  github = "<username>"
  linkedin = "<username>"
  xing = "<username>"
  medium = "<username>"
  twitter = "<username>"
  instagram = "<username>"
```
![landingpage-params](https://raw.githubusercontent.com/lgaida/mediumish-gohugo-theme/master/images/landing.png)


## Contributing

Feel free to use the [issue tracker](//github.com/lgaida/mediumish-gohugo-theme/issues) if you want to contribute in any possible way.
You can also create a [pull request](//github.com/lgaida/mediumish-gohugo-theme/pulls) if you have already implemented a new feature that you want to share.

## License

Like the original jekyll-theme this ported theme is released under the MIT License. Read more at the [License](//github.com/lgaida/mediumish-gohugo-theme/blob/master/LICENSE) itself.
