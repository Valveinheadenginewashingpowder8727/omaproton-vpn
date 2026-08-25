import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.grichard99.protonvpn"
  ipcTarget: "io.github.grichard99.protonvpn"
  manageIpc: false

  property string focusSection: "header"
  property int quickIndex: 0
  property int countryIndex: 0
  property int serverIndex: 0
  property bool cursorActive: false
  property string filterQuery: ""

  // Drilled into one country's server list rather than the country list.
  readonly property bool drilled: vpn.serversCountry !== ""
  // Row 0 inside a drill is "Fastest in <country>"; real servers follow it.
  readonly property int serverRowCount: drilled ? vpn.servers.length + 1 : 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color iconColor: vpn.connected ? foreground : dim
  readonly property color barIconColor: vpn.connected ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property var quickActions: [
    { key: "fastest", label: "Fastest", hint: "Best server for your location" },
    { key: "random", label: "Random", hint: "Any available server" },
    { key: "p2p", label: "P2P", hint: "Optimized for file sharing" },
    { key: "securecore", label: "Secure Core", hint: "Route via a privacy-friendly country" },
    { key: "tor", label: "Tor", hint: "Tor over VPN" }
  ]

  readonly property var filteredCountries: Model.filterCountries(vpn.countries, filterQuery)

  readonly property string heroMeta: {
    if (!vpn.installed) return "CLI not installed"
    if (vpn.busy && vpn.pendingLabel !== "") return vpn.pendingLabel
    if (vpn.connected) {
      var server = vpn.displayServer
      return server !== "" ? server : "Connected"
    }
    if (!vpn.accountProbed) return "Checking…"
    if (!vpn.signedIn) return "Signed out"
    return "Disconnected"
  }

  readonly property string toggleHint: vpn.connected ? "Disconnect" : "Connect to fastest server"

  function runQuick(key) {
    if (key === "fastest") vpn.connectFastest()
    else if (key === "random") vpn.connectRandom()
    else if (key === "p2p") vpn.connectP2P()
    else if (key === "securecore") vpn.connectSecureCore()
    else if (key === "tor") vpn.connectTor()
  }

  function ensureCursor() {
    if (!vpn.signedIn) {
      focusSection = "signin"
      return
    }
    if (focusSection === "signin") focusSection = "header"
    if (focusSection === "quick") {
      quickIndex = Math.max(0, Math.min(quickActions.length - 1, quickIndex))
    }
    if (focusSection === "countries") {
      if (drilled) { focusSection = "servers"; return }
      if (filteredCountries.length === 0) { focusSection = "quick"; return }
      countryIndex = Math.max(0, Math.min(filteredCountries.length - 1, countryIndex))
    }
    if (focusSection === "servers") {
      if (!drilled) { focusSection = "countries"; return }
      serverIndex = Math.max(0, Math.min(serverRowCount - 1, serverIndex))
    }
  }

  function drillInto(country) {
    if (!country) return
    cursorActive = true
    vpn.loadServers(country.code, country.name)
    focusSection = "servers"
    serverIndex = 0
    Qt.callLater(function() { if (panelFlick) panelFlick.contentY = 0 })
  }

  function drillOut() {
    vpn.clearServers()
    focusSection = "countries"
    serverIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()

    // Horizontal moves drill in and out of a country's server list.
    if (dx !== 0) {
      if (dx > 0 && focusSection === "countries") drillInto(filteredCountries[countryIndex])
      else if (dx < 0 && focusSection === "servers") drillOut()
      return
    }
    if (dy === 0) return

    if (focusSection === "signin") return

    if (focusSection === "header") {
      if (dy > 0) { focusSection = "quick"; quickIndex = 0; scrollCursorIntoView() }
      return
    }

    if (focusSection === "quick") {
      var next = quickIndex + dy
      if (next < 0) { focusSection = "header"; panelFlick.contentY = 0; return }
      if (next >= quickActions.length) {
        if (drilled && serverRowCount > 0) {
          focusSection = "servers"
          serverIndex = 0
          scrollCursorIntoView()
        } else if (filteredCountries.length > 0) {
          focusSection = "countries"
          countryIndex = 0
          scrollCursorIntoView()
        }
        return
      }
      quickIndex = next
      scrollCursorIntoView()
      return
    }

    if (focusSection === "countries") {
      var n = countryIndex + dy
      if (n < 0) {
        focusSection = "quick"
        quickIndex = quickActions.length - 1
        scrollCursorIntoView()
        return
      }
      countryIndex = Math.max(0, Math.min(filteredCountries.length - 1, n))
      scrollCursorIntoView()
      return
    }

    if (focusSection === "servers") {
      var m = serverIndex + dy
      if (m < 0) {
        focusSection = "quick"
        quickIndex = quickActions.length - 1
        scrollCursorIntoView()
        return
      }
      serverIndex = Math.max(0, Math.min(serverRowCount - 1, m))
      scrollCursorIntoView()
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "signin") vpn.signIn()
    else if (focusSection === "header") vpn.toggle()
    else if (focusSection === "quick") runQuick(quickActions[quickIndex].key)
    // Enter on a country opens its servers rather than connecting blind —
    // the first row inside is still "Fastest in <country>", so the old
    // one-keystroke behaviour is only ever one row away.
    else if (focusSection === "countries") drillInto(filteredCountries[countryIndex])
    else if (focusSection === "servers") activateServerRow(serverIndex)
  }

  function activateServerRow(index) {
    if (index <= 0) {
      vpn.connectCountry(vpn.serversCountry, vpn.serversCountryName)
      return
    }
    var s = vpn.servers[index - 1]
    if (s) vpn.connectServer(s.name)
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setQuickCursor(index) {
    cursorActive = true
    focusSection = "quick"
    quickIndex = index
  }

  function setCountryCursor(index) {
    cursorActive = true
    focusSection = "countries"
    countryIndex = index
  }

  function setServerCursor(index) {
    cursorActive = true
    focusSection = "servers"
    serverIndex = index
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "quick" && quickColumn && quickIndex >= 0 && quickIndex < quickColumn.children.length) {
      scrollItemIntoView(quickColumn.children[quickIndex])
    } else if (focusSection === "countries" && countryColumn && countryIndex >= 0 && countryIndex < countryColumn.children.length) {
      scrollItemIntoView(countryColumn.children[countryIndex])
    } else if (focusSection === "servers" && serverColumn && serverIndex >= 0 && serverIndex < serverColumn.children.length) {
      scrollItemIntoView(serverColumn.children[serverIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    vpn.panelOpen = opened
    if (opened) {
      cursorActive = false
      filterQuery = ""
      vpn.clearServers()
      serverIndex = 0
      if (panelFlick) panelFlick.contentY = 0
      ensureCursor()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onSignedInChanged() { root.ensureCursor() }
    function onCountriesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): string { vpn.connectFastest(); return "ok" }
    function disconnect(): string { vpn.disconnect(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    // Load one country's city list without opening the panel — opening it
    // steals keyboard focus, and a stray Space/Enter would connect somewhere.
    function servers(code: string): string {
      vpn.loadServers(code, code)
      return "ok"
    }
    function status(): string { return vpn.displayStatus + (vpn.displayServer !== "" ? " — " + vpn.displayServer : "") }
    // Deliberately omits the account email: anything running as this user can
    // call IPC, and the panel is the only place it should be readable.
    function debug(): string {
      return JSON.stringify({
        installed: vpn.installed,
        accountProbed: vpn.accountProbed,
        signedIn: vpn.signedIn,
        connected: vpn.connected,
        busy: vpn.busy,
        countries: vpn.countries.length,
        drilledInto: vpn.serversCountry,
        servers: vpn.servers.length,
        firstServer: vpn.servers.length > 0 ? vpn.servers[0].name + " " + vpn.servers[0].city + " " + vpn.servers[0].load + "%" : "",
        lastError: vpn.lastError
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ProtonIcon {
          anchors.centerIn: parent
          // The Proton mark is a solid triangle that fills its box corner to
          // corner, so it reads larger than the neighbouring glyphs at equal
          // size — trimmed to sit level with them.
          iconSize: Style.space(11)
          color: root.barIconColor
          opacity: vpn.connected ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggle()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The filter field owns the keyboard while it has focus, otherwise
      // every letter typed would drive the cursor instead of the query.
      blocked: filterField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      // Inside a drill, escape backs out one level before it closes the panel.
      onCloseRequested: root.drilled ? root.drillOut() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") { filterField.forceActiveFocus(); return }
        if (t === "c" || t === "C") vpn.connectFastest()
        else if (t === "d" || t === "D") vpn.disconnect()
        else if (t === "r" || t === "R") vpn.refresh()
        else if (t === "s" || t === "S") vpn.signIn()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, so
            // panel state is reached through `header` instead.
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Proton VPN"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.connected ? 1.0 : 0.5
              iconComponent: Component {
                ProtonIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: vpn.installed && vpn.signedIn
                  checked: vpn.connected
                  busy: vpn.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: vpn.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          SignInButton {
            // Held back until the account probe lands, and never shown over a
            // live tunnel — a connection is proof the session is valid.
            visible: vpn.installed && vpn.accountProbed && !vpn.signedIn && !vpn.connected
            width: parent.width
          }

          // Connection detail. Server and location are promoted out of the
          // status parse; everything else the CLI printed (Load, Protocol, …)
          // is rendered as-is.
          Column {
            visible: vpn.signedIn && vpn.connected
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Server"; value: vpn.displayServer }
            InfoPair { visible: vpn.location !== ""; label: "Location"; value: vpn.location }

            Repeater {
              model: vpn.fields
              InfoPair {
                required property var modelData
                label: modelData.label
                value: modelData.value
              }
            }
          }

          Column {
            visible: vpn.signedIn && vpn.account !== ""
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Account"; value: vpn.account }
            InfoPair { visible: vpn.plan !== ""; label: "Plan"; value: vpn.plan }
          }

          PanelSeparator {
            visible: vpn.signedIn
            foreground: root.foreground
          }

          Column {
            visible: vpn.signedIn
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "QUICK CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: quickColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.quickActions
                QuickRow {
                  required property var modelData
                  required property int index
                  width: quickColumn.width
                  action: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: vpn.signedIn
            foreground: root.foreground
          }

          Column {
            visible: vpn.signedIn
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.drilled ? String(vpn.serversCountryName).toUpperCase() : "COUNTRIES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            BackRow {
              visible: root.drilled
              width: parent.width
            }

            Text {
              visible: root.drilled && vpn.serversLoading
              width: parent.width
              text: "Loading servers…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: serverColumn
              visible: root.drilled && !vpn.serversLoading
              width: parent.width
              spacing: Style.space(6)

              FastestRow { width: serverColumn.width }

              Repeater {
                model: vpn.servers
                ServerRow {
                  required property var modelData
                  required property int index
                  width: serverColumn.width
                  server: modelData
                  // Row 0 is "Fastest in <country>", so servers start at 1.
                  rowIndex: index + 1
                }
              }
            }

            TextField {
              id: filterField
              visible: !root.drilled
              width: parent.width
              foreground: root.foreground
              placeholderText: vpn.countriesLoaded ? "Filter countries  (press /)" : "Loading countries…"
              enabled: vpn.countriesLoaded
              text: root.filterQuery
              onTextChanged: {
                root.filterQuery = text
                root.countryIndex = 0
              }
              Keys.onEscapePressed: function(event) {
                if (text !== "") text = ""
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) {
                var c = root.filteredCountries[0]
                if (c) {
                  vpn.connectCountry(c.code, c.name)
                  keyCatcher.forceActiveFocus()
                }
                event.accepted = true
              }
            }

            Text {
              visible: !root.drilled && vpn.countriesLoaded && root.filteredCountries.length === 0
              width: parent.width
              text: "No countries match."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: countryColumn
              visible: !root.drilled
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.filteredCountries
                CountryRow {
                  required property var modelData
                  required property int index
                  width: countryColumn.width
                  country: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component SignInButton: CursorSurface {
    id: signInButton

    hasCursor: root.cursorActive && root.focusSection === "signin"
    foreground: root.foreground

    implicitHeight: signInRow.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "signin"
      }
      onClicked: vpn.signIn()
    }

    RowLayout {
      id: signInRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰌆"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Sign in to Proton VPN"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: "Opens a terminal — password, then your 2FA token"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component QuickRow: CursorSurface {
    id: quickRow
    property var action: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "quick" && root.quickIndex === rowIndex
    foreground: root.foreground

    implicitHeight: quickContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setQuickCursor(quickRow.rowIndex)
      onClicked: root.runQuick(quickRow.action.key)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: quickContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: quickRow.action ? quickRow.action.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: quickRow.action ? quickRow.action.hint : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component CountryRow: CursorSurface {
    id: countryRow
    property var country: null
    property int rowIndex: 0

    readonly property bool isCurrent: vpn.connected && vpn.displayServer !== "" && country
                                      && vpn.displayServer.toUpperCase().indexOf(String(country.code).toUpperCase()) === 0

    hasCursor: root.cursorActive && root.focusSection === "countries" && root.countryIndex === rowIndex
    foreground: root.foreground

    implicitHeight: countryContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setCountryCursor(countryRow.rowIndex)
      onClicked: root.drillInto(countryRow.country)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: countryContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: countryRow.country ? countryRow.country.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Text {
        text: countryRow.isCurrent ? "󰄬" : (countryRow.country ? countryRow.country.code : "")
        color: countryRow.isCurrent ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      // Signals that the row opens a server list rather than connecting.
      Text {
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component BackRow: CursorSurface {
    id: backRow
    foreground: root.foreground
    implicitHeight: backLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.drillOut()
    }

    Text {
      id: backLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      text: "‹  All countries"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Row 0 of a drill: keeps the old one-click "fastest in this country" path.
  component FastestRow: CursorSurface {
    id: fastestRow
    hasCursor: root.cursorActive && root.focusSection === "servers" && root.serverIndex === 0
    foreground: root.foreground
    implicitHeight: fastestContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setServerCursor(0)
      onClicked: root.activateServerRow(0)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: fastestContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Fastest in " + vpn.serversCountryName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: vpn.servers.length > 0 ? vpn.servers.length + (vpn.servers.length === 1 ? " city" : " cities") + " available" : "Let Proton choose"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component ServerRow: CursorSurface {
    id: serverRow
    property var server: null
    property int rowIndex: 0

    // The row stands for a city, so any server in that city counts as current —
    // status reports "NL#42 in Amsterdam, Netherlands", so match on location.
    readonly property bool isCurrent: vpn.connected && server
                                      && (vpn.displayServer === server.name
                                          || (server.city !== "" && String(vpn.location).indexOf(server.city) === 0))

    hasCursor: root.cursorActive && root.focusSection === "servers" && root.serverIndex === rowIndex
    foreground: root.foreground
    implicitHeight: serverContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onEntered: root.setServerCursor(serverRow.rowIndex)
      onClicked: if (serverRow.server) vpn.connectServer(serverRow.server.name)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: serverContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: serverRow.server ? serverRow.server.city : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            if (!serverRow.server) return ""
            var bits = [serverRow.server.name]
            var tags = serverRow.server.tags || []
            if (tags.length > 0) bits.push(tags.join(", "))
            return bits.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        text: serverRow.isCurrent ? "󰄬" : (serverRow.server && serverRow.server.load !== undefined && serverRow.server.load !== null ? serverRow.server.load + "%" : "")
        color: {
          if (serverRow.isCurrent) return root.foreground
          var load = serverRow.server ? serverRow.server.load : 0
          return load >= 85 ? root.urgent : root.dim
        }
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
