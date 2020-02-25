// https://github.com/babel/babel/issues/9849
const regeneratorRuntime = require("regenerator-runtime");

document.querySelector("#autoComplete").addEventListener("autoComplete", event => {
    console.log('event:', event)
});

const autoCompletejs = new autoComplete({
    data: {
        src: async () => {
            const query = document.querySelector("#autoComplete").value;
            const source = await fetch(
                `/api/places?q=${query}`
            );
            let data = await source.json();
            data = [{ name: `Rechercher ${query} sur tout le site`, url: `/datasets?q=${query}` }, ...data]
            console.log('data:', data)
            return data;
        },
        key: ["name"],
        cache: false
    },
    selector: "#autoComplete",
    threshold: 1,
    debounce: 300,
    searchEngine: "strict",
    highlight: true,
    maxResults: 7,
    resultsList: {
        render: true,
        container: source => {
            source.setAttribute("id", "autoComplete_list");
        },
        destination: document.querySelector("#autoCompleteResults"),
        position: "beforeend",
        element: "ul"
    },
    resultItem: {
        content: (data, source) => {
            source.innerHTML = data.match;
        },
        element: "li"
    },
    noResults: () => {
        const result = document.createElement("li");
        result.setAttribute("class", "no_result");
        result.setAttribute("tabindex", "1");
        result.innerHTML = "Pas de lieu correspondant...";
        document.querySelector("#autoComplete_list").appendChild(result);
    },
    onSelection: feedback => {
        console.log('feedback:', feedback)
        feedback.event.preventDefault()
        window.location = feedback.selection.value.url
    }
});
