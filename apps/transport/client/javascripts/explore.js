import { Socket } from 'phoenix'

let socket = new Socket("/socket", { params: { token: window.userToken } });
socket.connect();
let channel = socket.channel("explore", {})
channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })

channel.on("hello", payload => {
    console.log("hello received", payload);
})

export default socket