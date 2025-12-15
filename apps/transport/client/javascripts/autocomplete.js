/* eslint no-unused-vars: [2, {"args": "after-used", "varsIgnorePattern": "autoCompletejs"}] */
/* global contactId */
// https://github.com/babel/babel/issues/9849
require('regenerator-runtime')
const AutoComplete = require('@tarekraafat/autocomplete.js/dist/autoComplete')

const labels = {
    region: 'région',
    departement: 'département',
    epci: 'EPCI',
    commune: 'commune',
    feature: 'données contenant…',
    mode: 'mode de transport',
    offer: 'offre de transport',
    format: 'format de données'
}

document.onkeydown = function (evt) {
    evt = evt || window.event
    if (evt.key === 'Escape' || evt.key === 'Esc') {
        document.querySelector('#autoComplete').value = ''
        document.querySelector('#autoComplete_list').innerHTML = ''
    }
}

const autoCompletejs = new AutoComplete({
    data: {
        src: async () => {
            const query = document.querySelector('#autoComplete').value
            const source = await fetch(`/api/autocomplete?q=${query}`)
            let data = await source.json()
            data = [
                {
                    name: `Rechercher ${query} dans les descriptions des jeux de données`,
                    value: query,
                    type: 'description',
                    position: 1,
                    url: `/datasets?q=${query}`
                },
                ...data.map((el, index) => {
                    return {
                        ...el,
                        value: el.name,
                        position: index + 2
                    }
                })
            ]
            return data
        },
        key: ['name'],
        cache: false
    },
    selector: '#autoComplete',
    threshold: 1,
    debounce: 200,
    highlight: true,
    searchEngine: (query, record) => {
        record = record.name
        // inspired by the 'loose' searchEngine, but that always matches
        query = query.replace(/ /g, '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        const recordLowerCase = record.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        const fullMatchPos = recordLowerCase.indexOf(query)
        if (fullMatchPos >= 0) {
            // full query match has priority
            return `${record.slice(0, fullMatchPos)}<span class="autoComplete_highlighted">${record.slice(fullMatchPos, fullMatchPos + query.length)}</span>${record.slice(fullMatchPos + query.length)}`
        } else {
            const match = []
            let searchPosition = 0
            for (let number = 0; number < recordLowerCase.length; number++) {
                let recordChar = record[number]
                if (
                    searchPosition < query.length &&
                    recordLowerCase[number] === query[searchPosition]
                ) {
                    recordChar = `<span class="autoComplete_highlighted">${recordChar}</span>`
                    searchPosition++
                }
                match.push(recordChar)
            }
            return match.join('')
        }
    },
    resultsList: {
        maxResults: 7,
        id: 'autoComplete_list',
        destination: '#autoCompleteResults',
        position: 'beforeend',
        tag: 'ul'
    },
    resultItem: {
        element: (source, data) => {
            source.innerHTML = `<div><span class="autocomplete_name">${data.match}</span><span class="autocomplete_type">${labels[data.value.type] || ''}</span></div>`
        },
        tag: 'li',
        highlight: 'autoComplete_highlight',
        selected: 'autoComplete_selected'
    }
})

document.querySelector('#autoComplete').addEventListener('selection', function (event) {
    const selection = event.detail.selection.value

    // Log the selected value
    fetch('/api/features/autocomplete', {
        method: 'POST',
        headers: {
            'content-type': 'application/json'
        },
        body: JSON.stringify({
            ...selection,
            contact_id: contactId
        })
    })

    // Redirect to the target URL
    window.location = selection.url
})
