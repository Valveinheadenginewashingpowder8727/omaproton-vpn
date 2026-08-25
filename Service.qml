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
//
// Every subprocess is an argv list. The one place a value crosses a shell
// boundary is sign-in, where the username is whitelisted and single-quoted
// before it reaches the terminal launcher.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool installed: false
  property bool installing: false
  // The GTK app and the CLI share one backend and can't run at the same time;
  // a user who installed the app from Proton's site hits an opaque failure.
  property bool gtkAppInstalled: false

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

  // `protonvpn config list`, keyed by setting name.
  property var config: ({})
  property bool configLoaded: false
  readonly property bool killSwitchOn: String(config["kill-switch"] || "") === "standard"
  readonly property bool netShieldOn: configLoaded && String(config["netshield"] || "off") !== "off"
  // The only values setConfig() will ever pass to the CLI.
  readonly property var configValues: ({
    "kill-switch": ["off", "standard"],
    "netshield": ["off", "malware-only", "malware-ads-trackers"]
  })

  // Persisted across restarts: last few places connected to, and whether the
  // kill-switch nudge was dismissed. Location labels only — nothing secret.
  property var recents: []
  property bool nudgeDismissed: false
  property bool stateLoaded: false
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-protonvpn"
  readonly property string statePath: stateDir + "/state.json"

  readonly property string scriptPath: Qt.resolvedUrl("servers.py").toString().replace(/^file:\/\//, "")

  property string actionStatus: ""
  property string lastError: ""
  property string pendingLabel: ""

  // -1 = follow reality; 0/1 = a requested state still catching up.
  property int _desired: -1
  // Set when we asked for the tunnel to go down, so the drop isn't reported
  // as a failure.
  property bool _expectDown: false
  // What the in-flight connect was asked for, recorded to recents on success.
  property var _target: null
  property string _configKey: ""
  property string _configValue: ""

  readonly property bool connected: _desired === -1 ? (linkActive || statusConnected) : (_desired === 1)
  readonly property bool busy: actionProcess.running || connectProcess.running
  readonly property bool refreshing: statusProcess.running
  readonly property bool configBusy: setConfigProcess.running

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int watchIntervalSec: intSetting("watchIntervalSec", 4, 2, 60)
  readonly property bool notificationsOn: String(setting("notifications", "on")) !== "off"

  // The server line from nmcli is live even mid-`connect`; prefer it, and fall
  // back to the status parse when the link is down.
  readonly property string displayServer: linkActive && linkServer !== "" ? linkServer : serverName
  // Observed state outranks account state: a live tunnel is a fact, while
  // signedIn is unknown until the first probe returns.
  readonly property string displayStatus: {
    if (!installed) return "Not installed"
    if (busy && pendingLabel !== "") return pendingLabel
    if (connected) return "Protected"
    if (statusConnecting) return "Connecting…"
    if (!accountProbed) return "Checking…"
    if (!signedIn) return "Signed out"
    return "Not protected"
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
      probeInstalled()
      return
    }
    watchLink()
    refreshStatus()
    refreshAccount()
  }

  function probeInstalled() {
    if (!whichProcess.running) {
      whichProcess.command = ["which", "protonvpn"]
      whichProcess.running = true
    }
    if (!pacmanProcess.running) {
      pacmanProcess.command = ["pacman", "-Q", "proton-vpn-gtk-app"]
      pacmanProcess.running = true
    }
  }

  // Omarchy's own installer flow: a floating terminal owns the sudo prompt,
  // so the shell process never touches privileges.
  function installCli() {
    if (installed || installing) return
    installing = true
    lastError = ""
    Quickshell.execDetached(["omarchy-install-app", "Proton VPN CLI", "proton-vpn-cli"])
    installWatch.restart()
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

  function loadConfig() {
    if (!installed || !signedIn || configProcess.running) return
    configProcess.command = ["protonvpn", "config", "list"]
    configProcess.running = true
  }

  // Both key and value must be in configValues; anything else is dropped.
  function setConfig(key, value) {
    var allowed = configValues[key]
    if (!allowed || allowed.indexOf(value) === -1) return
    if (!installed || !signedIn || setConfigProcess.running) return
    _configKey = key
    _configValue = value
    lastError = ""
    setConfigProcess.command = ["protonvpn", "config", "set", key, value]
    setConfigProcess.running = true
  }

  function toggleKillSwitch() { setConfig("kill-switch", killSwitchOn ? "off" : "standard") }
  // Full protection first; the CLI refuses ads/trackers on a free plan and
  // the retry below steps down to malware-only.
  function toggleNetShield() { setConfig("netshield", netShieldOn ? "off" : "malware-ads-trackers") }

  function dismissNudge() {
    nudgeDismissed = true
    saveState()
  }

  function toggle() {
    if (!installed || busy) return
    // A live tunnel is proof of a session, so never send an already-signed-in
    // user to a sign-in prompt just because the account probe is stale or
    // briefly failed. Only offer sign-in once we've probed AND there's no link.
    if (!signedIn && !connected) {
      if (accountProbed) signIn("")
      else refreshAccount()
      return
    }
    if (connected) disconnect()
    else connectTo([], "Connecting to fastest…", null)
  }

  // target: {key, title, subtitle, args} recorded to recents on success, or
  // null for quick actions that are already one click away.
  function connectTo(args, label, target) {
    if (!installed || !signedIn || busy) return
    _desired = 1
    _expectDown = false
    _target = target
    pendingLabel = label || "Connecting…"
    actionStatus = pendingLabel
    lastError = ""
    connectProcess.command = ["protonvpn", "connect"].concat(args || [])
    connectProcess.running = true
  }

  function connectFastest() { connectTo([], "Connecting to fastest…", null) }
  function connectRandom() { connectTo(["--random"], "Connecting to a random server…", null) }
  function connectP2P() { connectTo(["--p2p"], "Connecting to fastest P2P…", null) }
  function connectSecureCore() { connectTo(["--securecore"], "Connecting via Secure Core…", null) }
  function connectTor() { connectTo(["--tor"], "Connecting via Tor…", null) }

  function connectCountry(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (c === "") return
    var title = name || c
    connectTo(["--country", c], "Connecting to " + title + "…",
              { key: "country:" + c, title: title, subtitle: "Fastest server", args: ["--country", c] })
  }

  // `protonvpn connect <NAME>` takes precedence over every filter in the CLI's
  // own selection, so a named server connects exactly as asked. City and
  // country are only for the label people see.
  function connectServer(name, city, countryName) {
    var n = String(name || "").trim()
    if (n === "") return
    var title = city || n
    var subtitle = [countryName, n].filter(function(s) { return s }).join(" · ")
    connectTo([n], "Connecting to " + title + "…",
              { key: "server:" + n, title: title, subtitle: subtitle, args: [n] })
  }

  function connectRecent(index) {
    var r = recents[index]
    if (!r || !Array.isArray(r.args)) return
    connectTo(r.args, "Connecting to " + r.title + "…", r)
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
    _expectDown = true
    pendingLabel = "Disconnecting…"
    actionStatus = ""
    lastError = ""
    actionProcess.command = ["protonvpn", "disconnect"]
    actionProcess.running = true
  }

  // Sign-in is interactive (password, then a TOTP token), so it has to happen
  // in a real terminal — the CLI only accepts them from a tty. The username
  // can be typed in the panel; with none given the terminal asks for it.
  function signIn(username) {
    var u = String(username || "").trim()
    var cmd
    if (u === "") {
      cmd = "read -rp 'Proton username: ' u && protonvpn signin \"$u\""
    } else if (Model.validUsername(u)) {
      cmd = "protonvpn signin " + Model.shellQuote(u)
    } else {
      lastError = "Usernames can only contain letters, numbers and . _ + @ -"
      return false
    }
    lastError = ""
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", cmd])
    signInWatch.restart()
    return true
  }

  function signOut() {
    if (!installed || busy) return
    _desired = 0
    _expectDown = true
    pendingLabel = "Signing out…"
    actionProcess.command = ["protonvpn", "signout"]
    actionProcess.running = true
  }

  function notify(summary, body, urgency) {
    if (!notificationsOn) return
    Quickshell.execDetached(["notify-send", "-a", "Proton VPN", "-i", "network-vpn",
                             "-u", urgency || "normal", summary, body || ""])
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

  function applyState(text) {
    try {
      var s = JSON.parse(String(text || "{}"))
      recents = Array.isArray(s.recents) ? s.recents.slice(0, 3) : []
      nudgeDismissed = s.killSwitchNudgeDismissed === true
    } catch (e) {
      recents = []
      nudgeDismissed = false
    }
    stateLoaded = true
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ recents: recents, killSwitchNudgeDismissed: nudgeDismissed }))
  }

  function recordRecent(target) {
    if (!target || !target.key) return
    var next = [target]
    for (var i = 0; i < recents.length && next.length < 3; i++) {
      if (recents[i] && recents[i].key !== target.key) next.push(recents[i])
    }
    recents = next
    saveState()
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    refresh()
  }

  onPanelOpenChanged: if (panelOpen) {
    refresh()
    loadCountries(false)
    loadConfig()
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("{}")
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

  // Same idea for the package install: up to five minutes for pacman.
  Timer {
    id: installWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.probeInstalled()
      if (root.installed || ticks > 100) {
        stop()
        root.installing = false
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      var was = root.installed
      root.installed = exitCode === 0
      if (root.installed) {
        if (!was) {
          root.installing = false
          root.lastError = ""
          root.statusText = "Checking…"
        }
        root.refresh()
      } else if (!root.installing) {
        root.statusText = "Proton VPN CLI not installed"
      }
    }
  }

  Process {
    id: pacmanProcess
    running: false
    command: []
    onExited: function(exitCode) { root.gtkAppInstalled = exitCode === 0 }
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
      // A tunnel we didn't ask to close is the one thing a person must hear
      // about: the icon dimming is not a signal most people read.
      if (was && !link.active) {
        if (!root._expectDown && !actionProcess.running)
          root.notify("Proton VPN disconnected", "You're no longer protected.", "critical")
        root._expectDown = false
      }
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
      if (info.signedIn && !was) {
        root.loadCountries(true)
        root.loadConfig()
      }
      if (!info.signedIn) {
        root.countries = []
        root.countriesLoaded = false
        root.config = {}
        root.configLoaded = false
      }
    }
  }

  Process {
    id: configProcess
    running: false
    command: []
    stdout: StdioCollector { id: configStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.config = Model.parseConfig(String(configStdout.text || ""))
      root.configLoaded = true
    }
  }

  Process {
    id: setConfigProcess
    running: false
    command: []
    stdout: StdioCollector { id: setConfigStdout; waitForEnd: true }
    stderr: StdioCollector { id: setConfigStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(setConfigStderr.text || "") || String(setConfigStdout.text || "")
      var key = root._configKey
      var value = root._configValue
      root._configKey = ""
      root._configValue = ""
      if (exitCode !== 0) {
        if (key === "netshield" && value === "malware-ads-trackers" && Model.isPlanError(err)) {
          root.setConfig("netshield", "malware-only")
          return
        }
        root.lastError = Model.isPlanError(err) ? "Requires a Proton VPN Plus plan" : Model.elide(err || "Setting failed")
      }
      root.loadConfig()
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
      var target = root._target
      root._target = null
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root._desired = -1
        var text = err || out || "Connect failed"
        root.lastError = Model.isPlanError(text) ? "Requires a Proton VPN Plus plan" : Model.elide(text)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        // First line is "Connected to <server> in <city>, <country>."
        var line = Model.elide(out.split("\n")[0] || "", 90)
        root.actionStatus = line
        actionStatusTimer.restart()
        root.recordRecent(target)
        root.notify("Protected", line, "normal")
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
        root._expectDown = false
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
