import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Proton VPN state for the bar widget.
//
// Two polls with different costs drive this:
//
//   * nmcli (~10ms) runs on a short interval and owns the bar icon. The CLI
//     names its tunnel "ProtonVPN <server>" on device proton0, so this alone
//     answers "are we up, and where" without paying for the Python CLI.
//   * `protonvpn status` (~1s of Python start-up) runs only when the panel is
//     open, on demand, and after an action — it supplies the detail rows.
//
// `protonvpn connect` blocks for 30-60s, so every action is optimistic:
// _desired pins the UI to the requested state until reality agrees.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool installed: false
  property bool signedIn: false
  // `protonvpn info` costs ~1s, so signedIn is false-but-unknown until the
  // first probe lands. Without this the widget briefly claims "Signed out"
  // over a tunnel that is plainly up.
  property bool accountProbed: false
  property string account: ""
  property string plan: ""

  // nmcli-derived, fast
  property bool linkActive: false
  property string linkServer: ""

  // `protonvpn status`-derived, slow
  property bool statusConnected: false
  property bool statusConnecting: false
  property string statusText: "Checking…"
  property string serverName: ""
  property string location: ""
  property var fields: []

  property var countries: []
  property bool countriesLoaded: false

  // Server drill-down for one country, read from the client's own cache.
  property var servers: []
  property string serversCountry: ""
  property string serversCountryName: ""
  property bool serversLoading: false

  readonly property string scriptPath: Qt.resolvedUrl("servers.py").toString().replace(/^file:\/\//, "")

  property string actionStatus: ""
  property string lastError: ""
  property string pendingLabel: ""

  // -1 = follow reality; 0/1 = a requested state still catching up.
  property int _desired: -1
  readonly property bool connected: _desired === -1 ? (linkActive || statusConnected) : (_desired === 1)
  readonly property bool busy: actionProcess.running || connectProcess.running
  readonly property bool refreshing: statusProcess.running

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int watchIntervalSec: intSetting("watchIntervalSec", 4, 2, 60)

  // The server line from nmcli is live even mid-`connect`; prefer it, and fall
  // back to the status parse when the link is down.
  readonly property string displayServer: linkActive && linkServer !== "" ? linkServer : serverName
  // Observed state outranks account state: a live tunnel is a fact, while
  // signedIn is unknown until the first probe returns.
  readonly property string displayStatus: {
    if (!installed) return "CLI not installed"
    if (busy && pendingLabel !== "") return pendingLabel
    if (connected) return "Connected"
    if (statusConnecting) return "Connecting…"
    if (!accountProbed) return "Checking…"
    if (!signedIn) return "Signed out"
    return "Disconnected"
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) {
        whichProcess.command = ["which", "protonvpn"]
        whichProcess.running = true
      }
      return
    }
    watchLink()
    refreshStatus()
    refreshAccount()
  }

  function watchLink() {
    if (watchProcess.running) return
    watchProcess.command = ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"]
    watchProcess.running = true
  }

  function refreshStatus() {
    if (!installed || statusProcess.running) return
    statusProcess.command = ["protonvpn", "status"]
    statusProcess.running = true
  }

  function refreshAccount() {
    if (!installed || accountProcess.running) return
    accountProcess.command = ["protonvpn", "info"]
    accountProcess.running = true
  }

  function loadCountries(force) {
    if (!installed || !signedIn || countriesProcess.running) return
    if (countriesLoaded && force !== true) return
    countriesProcess.command = ["protonvpn", "countries", "list"]
    countriesProcess.running = true
  }

  function toggle() {
    if (!installed || busy) return
    // A live tunnel is proof of a session, so never send an already-signed-in
    // user to a sign-in prompt just because the account probe is stale or
    // briefly failed. Only offer sign-in once we've probed AND there's no link.
    if (!signedIn && !connected) {
      if (accountProbed) signIn()
      else refreshAccount()
      return
    }
    if (connected) disconnect()
    else connectTo([], "Connecting to fastest…")
  }

  function connectTo(args, label) {
    if (!installed || !signedIn || busy) return
    _desired = 1
    pendingLabel = label || "Connecting…"
    actionStatus = pendingLabel
    lastError = ""
    connectProcess.command = ["protonvpn", "connect"].concat(args || [])
    connectProcess.running = true
  }

  function connectFastest() { connectTo([], "Connecting to fastest…") }
  function connectRandom() { connectTo(["--random"], "Connecting to a random server…") }
  function connectP2P() { connectTo(["--p2p"], "Connecting to fastest P2P…") }
  function connectSecureCore() { connectTo(["--securecore"], "Connecting via Secure Core…") }
  function connectTor() { connectTo(["--tor"], "Connecting via Tor…") }
  function connectCountry(code, name) {
    var c = String(code || "").trim()
    if (c === "") return
    connectTo(["--country", c], "Connecting to " + (name || c) + "…")
  }

  // `protonvpn connect <NAME>` takes precedence over every filter in the CLI's
  // own selection, so a named server connects exactly as asked.
  function connectServer(name) {
    var n = String(name || "").trim()
    if (n === "") return
    connectTo([n], "Connecting to " + n + "…")
  }

  function loadServers(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (!installed || c === "" || serversProcess.running) return
    serversCountry = c
    serversCountryName = name || c
    servers = []
    serversLoading = true
    serversProcess.command = ["python3", scriptPath, c, "80"]
    serversProcess.running = true
  }

  function clearServers() {
    servers = []
    serversCountry = ""
    serversCountryName = ""
    serversLoading = false
  }

  function disconnect() {
    if (!installed || busy) return
    _desired = 0
    pendingLabel = "Disconnecting…"
    actionStatus = ""
    lastError = ""
    actionProcess.command = ["protonvpn", "disconnect"]
    actionProcess.running = true
  }

  // Sign-in is interactive (password, then a TOTP token), so it has to happen
  // in a real terminal — the CLI only accepts them from a tty.
  function signIn() {
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      "read -rp 'Proton username: ' u && protonvpn signin \"$u\""
    ])
    signInWatch.restart()
  }

  function signOut() {
    if (!installed || busy) return
    _desired = 0
    pendingLabel = "Signing out…"
    actionProcess.command = ["protonvpn", "signout"]
    actionProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    statusConnected = parsed.connected
    statusConnecting = parsed.connecting
    statusText = parsed.statusText
    serverName = parsed.serverName
    location = parsed.location
    fields = parsed.fields
    reconcile()
  }

  // Drop the optimistic override as soon as the world agrees with it.
  function reconcile() {
    if (_desired === -1) return
    var real = linkActive || statusConnected
    if (real === (_desired === 1)) {
      _desired = -1
      pendingLabel = ""
    }
  }

  Component.onCompleted: refresh()

  onPanelOpenChanged: if (panelOpen) {
    refresh()
    loadCountries(false)
  }

  Timer {
    id: watchTimer
    interval: root.watchIntervalSec * 1000
    repeat: true
    running: root.installed
    triggeredOnStart: true
    onTriggered: root.watchLink()
  }

  Timer {
    id: statusTimer
    // Cheap enough to keep current while the panel is open; throttled back to
    // the configured interval once it closes.
    interval: (root.panelOpen ? 5 : root.refreshIntervalSec) * 1000
    repeat: true
    running: root.installed && root.signedIn
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: delayedRefresh
    interval: 1200
    repeat: false
    onTriggered: {
      root.watchLink()
      root.refreshStatus()
    }
  }

  Timer {
    id: accountRetry
    interval: 5000
    repeat: false
    onTriggered: root.refreshAccount()
  }

  Timer {
    id: actionStatusTimer
    interval: 6000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  // Sign-in happens out of process in a terminal; poll for a while so the
  // panel flips to the signed-in view on its own.
  Timer {
    id: signInWatch
    interval: 3000
    repeat: true
    triggeredOnStart: false
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refreshAccount()
      if (root.signedIn || ticks > 40) stop()
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else {
        root.statusText = "Proton VPN CLI not installed"
        root.lastError = "Install it with: omarchy pkg add proton-vpn-cli"
      }
    }
  }

  Process {
    id: watchProcess
    running: false
    command: []
    stdout: StdioCollector { id: watchStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var link = Model.parseActiveVpn(String(watchStdout.text || ""))
      var was = root.linkActive
      root.linkActive = link.active
      root.linkServer = link.server
      root.reconcile()
      // The tunnel came up or went away behind our back (CLI in a terminal,
      // a drop, a reconnect) — pull the detail rows back in sync.
      if (was !== link.active) root.refreshStatus()
      // A tunnel we didn't think we were signed in for means the account
      // state is wrong, not the link. Re-probe rather than trusting it.
      if (link.active && !root.signedIn) root.refreshAccount()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.applyStatus(String(statusStdout.text || ""))
        root.lastError = ""
      } else {
        root.lastError = Model.elide(String(statusStderr.text || "") || "protonvpn status failed")
      }
    }
  }

  Process {
    id: accountProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountStdout; waitForEnd: true }
    onExited: function(exitCode) {
      // A one-off failure must not latch "signed out" forever — retry instead
      // of leaving a signed-in user staring at a sign-in prompt.
      if (exitCode !== 0) { accountRetry.restart(); return }
      var info = Model.parseAccount(String(accountStdout.text || ""))
      var was = root.signedIn
      root.accountProbed = true
      root.signedIn = info.signedIn
      root.account = info.account
      root.plan = info.plan
      if (info.signedIn && !was) root.loadCountries(true)
      if (!info.signedIn) {
        root.countries = []
        root.countriesLoaded = false
      }
    }
  }

  Process {
    id: serversProcess
    running: false
    command: []
    stdout: StdioCollector { id: serversStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.serversLoading = false
      if (exitCode !== 0) { root.servers = []; return }
      try {
        root.servers = JSON.parse(String(serversStdout.text || "[]"))
      } catch (e) {
        root.servers = []
      }
    }
  }

  Process {
    id: countriesProcess
    running: false
    command: []
    stdout: StdioCollector { id: countriesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var list = Model.parseCountries(String(countriesStdout.text || ""))
      root.countries = list
      root.countriesLoaded = list.length > 0
    }
  }

  Process {
    id: connectProcess
    running: false
    command: []
    stdout: StdioCollector { id: connectStdout; waitForEnd: true }
    stderr: StdioCollector { id: connectStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(connectStdout.text || "")
      var err = String(connectStderr.text || "")
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = Model.elide(err || out || "Connect failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        // First line is "Connected to <server> in <city>, <country>."
        root.actionStatus = Model.elide(out.split("\n")[0] || "", 90)
        actionStatusTimer.restart()
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(actionStdout.text || "")
      var err = String(actionStderr.text || "")
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = Model.elide(err || out || "Command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.refreshAccount()
      delayedRefresh.restart()
    }
  }
}
