var addSeeMore = function (maxHeight, querySelector, seeMoreText, seeLessText) {
    document.querySelectorAll(querySelector).forEach(
        function (div) {
            div.style.maxHeight = maxHeight
            div.style.overflow = "hidden"
            if (div.scrollHeight > div.clientHeight) {
                var parent = div.parentElement
                var displayMore = document.createElement("div")
                parent.appendChild(displayMore)
                displayMore.className = ".displayMore"
                var link_displayMore = document.createElement("a")
                displayMore.appendChild(link_displayMore)
                link_displayMore.innerHTML = seeMoreText
                displayMore.addEventListener("click",
                    function () {
                        if (div.style.maxHeight != "100%") {
                            div.style.maxHeight = "100%";
                            link_displayMore.innerHTML = seeLessText
                        } else {
                            div.style.maxHeight = maxHeight
                            link_displayMore.innerHTML = seeMoreText
                        }
                    }
                )
            }
        }
    )
}
// make the function available in templates
window.addSeeMore = addSeeMore
