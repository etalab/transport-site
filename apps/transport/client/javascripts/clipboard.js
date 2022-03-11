import Clipboard from 'clipboard'

const clipboard = new Clipboard('.button')
clipboard.on('success', e => {
    e.trigger.textContent = 'Ok!'
    e.clearSelection()
})
