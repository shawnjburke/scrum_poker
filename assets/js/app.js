// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/scrum_poker"
import topbar from "../vendor/topbar"

let Hooks = {
  ...colocatedHooks,
  CopyToClipboard: {
    mounted() {
      this.el.addEventListener("click", () => {
        const text = this.el.dataset.copyText
        if (text && navigator.clipboard) {
          navigator.clipboard.writeText(text).then(() => {
            const orig = this.el.innerHTML
            this.el.innerHTML = "✓ Copied!"
            setTimeout(() => { this.el.innerHTML = orig }, 1500)
          })
        }
      })
    }
  },
  ClearOnSubmit: {
    mounted() {
      this.el.form.addEventListener("submit", () => {
        setTimeout(() => { this.el.value = "" }, 0)
      })
    }
  },
  Confetti: {
    mounted() {
      const canvas = document.createElement("canvas")
      canvas.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:9999"
      document.body.appendChild(canvas)
      const ctx = canvas.getContext("2d")
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight

      const colors = ["#ff6b6b","#feca57","#48dbfb","#ff9ff3","#54a0ff","#5f27cd","#01a3a4","#f368e0","#00d2d3","#ff6348"]
      const particles = Array.from({length: 150}, () => ({
        x: canvas.width / 2 + (Math.random() - 0.5) * 300,
        y: canvas.height / 2 + 50,
        vx: (Math.random() - 0.5) * 16,
        vy: Math.random() * -18 - 4,
        size: Math.random() * 8 + 3,
        color: colors[Math.floor(Math.random() * colors.length)],
        rot: Math.random() * 360,
        rotV: (Math.random() - 0.5) * 12,
        opacity: 1
      }))

      const animate = () => {
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        let alive = false
        for (const p of particles) {
          p.x += p.vx
          p.vx *= 0.99
          p.vy += 0.35
          p.y += p.vy
          p.rot += p.rotV
          p.opacity -= 0.006
          if (p.opacity > 0 && p.y < canvas.height + 100) {
            alive = true
            ctx.save()
            ctx.translate(p.x, p.y)
            ctx.rotate(p.rot * Math.PI / 180)
            ctx.globalAlpha = Math.max(0, p.opacity)
            ctx.fillStyle = p.color
            ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6)
            ctx.restore()
          }
        }
        if (alive) requestAnimationFrame(animate)
        else canvas.remove()
      }
      requestAnimationFrame(animate)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

