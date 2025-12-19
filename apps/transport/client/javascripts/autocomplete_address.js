const AutoComplete = require('@tarekraafat/autocomplete.js/dist/autoComplete')

// eslint-disable-next-line no-new
new AutoComplete({
    data: {
        src: async () => {
            const query = document.querySelector('#autoComplete').value
            // See https://geoservices.ign.fr/documentation/services/services-geoplateforme/autocompletion
            const source = await fetch(`https://data.geopf.fr/geocodage/completion/?text=${query}&poiType=administratif&type=StreetAddress&maximumResponses=5`)
            const data = await source.json()
            return data.results
        },
        keys: ['fulltext'],
        cache: false
    },
    selector: '#autoComplete',
    threshold: 3,
    debounce: 200,
    highlight: true,
    submit: false,
    resultsList: {
        maxResults: 5,
        id: 'autoComplete_list',
        class: 'no_legend',
        destination: '#autoCompleteResults',
        position: 'beforeend',
        tag: 'ul',
        noResults: true,
        element: (list, data) => {
            if (!data.results.length) {
                const message = document.createElement('li')
                message.innerHTML = `Pas de résultats pour "<span class="autoComplete_highlighted">${data.query}</span>"`
                list.prepend(message)
            }
        }
    },
    resultItem: {
        element: (source, data) => {
            source.innerHTML = `<div><span class="autocomplete_name">${data.match}</span><span class="autocomplete_type">adresse</span></div>`
        },
        tag: 'li',
        highlight: 'autoComplete_highlighted',
        selected: 'autoComplete_selected'
    }
})

document.addEventListener('keydown', function (event) {
    if (event.key === '/' && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
        const searchInput = document.getElementById('autoComplete')
        if (searchInput) {
            event.preventDefault()
            searchInput.focus()
        }
    }
})
