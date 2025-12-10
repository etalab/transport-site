/* eslint no-unused-vars: [2, {"args": "after-used", "varsIgnorePattern": "autoCompletejs"}] */
/* global contactId */
// https://github.com/babel/babel/issues/9849
require('regenerator-runtime')
const AutoComplete = require('@tarekraafat/autocomplete.js/dist/js/autoComplete')

const labels = {
    region: 'région',
    departement: 'département',
    epci: 'EPCI',
    commune: 'commune',
    feature: 'données contenant…',
    mode: 'mode de transport',
    offer: 'offre de transport'
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
                    url: `/datasets?q=${query}`
                },
                ...data
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
    maxResults: 7,
    resultsList: {
        render: true,
        container: source => {
            source.setAttribute('id', 'autoComplete_list')
        },
        destination: document.querySelector('#autoCompleteResults'),
        position: 'beforeend',
        element: 'ul'
    },
    resultItem: {
        content: (data, source) => {
            source.innerHTML = `<div><span class="autocomplete_name">${data.match}</span><span class="autocomplete_type">${labels[data.value.type] || ''}</span></div>`
        },
        element: 'li'
    },
    onSelection: feedback => {
        feedback.event.preventDefault()

        const selection = feedback.selection.value

        let payload = {}
        if (selection.type === 'description') {
            payload = {
                name: selection.value,
                type: selection.type,
                contact_id: contactId
            }
        } else {
            payload = {
                name: selection.name,
                type: selection.type,
                contact_id: contactId
            }
        }

        // Log the selected value
        fetch('/api/features/autocomplete', {
            method: 'POST',
            headers: {
                'content-type': 'application/json'
            },
            body: JSON.stringify(payload)
        })

        // Redirect to the target URL
        window.location = selection.url
    }
})
