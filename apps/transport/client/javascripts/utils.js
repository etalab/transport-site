var addSeeMore = function (maxHeight, querySelector, seeMoreText, seeLessText) {
    document.querySelectorAll(querySelector).forEach(
        function (div) {
            div.style.maxHeight = maxHeight
            div.style.overflow = 'hidden'
            if (div.scrollHeight > div.clientHeight) {
                var parent = div.parentElement
                var displayMore = document.createElement('div')
                parent.appendChild(displayMore)
                displayMore.className = '.displayMore'
                var linkDisplayMore = document.createElement('a')
                displayMore.appendChild(linkDisplayMore)
                linkDisplayMore.innerHTML = seeMoreText
                displayMore.addEventListener('click',
                    function () {
                        if (div.style.maxHeight !== '100%') {
                            div.style.maxHeight = '100%'
                            linkDisplayMore.innerHTML = seeLessText
                        } else {
                            div.style.maxHeight = maxHeight
                            linkDisplayMore.innerHTML = seeMoreText
                        }
                    }
                )
            }
        }
    )
}
// make the function available in templates
window.addSeeMore = addSeeMore
