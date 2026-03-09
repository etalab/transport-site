const buttons = [document.getElementById('enter-fullscreen'), document.getElementById('exit-fullscreen')]
buttons.forEach(button => {
    button.addEventListener('click', () => {
        if (document.fullscreenElement) {
            document.exitFullscreen()
        } else {
            document.body.requestFullscreen()
        }
    })
})
