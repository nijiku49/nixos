{ pkgs, lib, config, ... }:

let
  quickshell = pkgs.quickshell;
  theme = import ./theme-script.nix { inherit pkgs lib config; };

  # wifi через iwd: status / list / connect / disconnect / forget / power
  wifiScript = pkgs.writeShellScript "qs-wifi" ''
    export PATH=${lib.makeBinPath [ pkgs.iwd pkgs.gawk pkgs.gnused pkgs.coreutils ]}:$PATH

    dev=""
    for d in /sys/class/net/*; do
      if [ -d "$d/wireless" ]; then dev=$(basename "$d"); break; fi
    done

    strip() { sed 's/\x1b\[[0-9;]*m//g'; }

    cmd=status
    [ $# -gt 0 ] && cmd=$1

    case "$cmd" in
      status)
        # кабель: первый ethernet-интерфейс и его состояние
        for e in /sys/class/net/en*; do
          [ -e "$e" ] || continue
          echo "wired $(cat "$e/operstate" 2>/dev/null)"
          break
        done
        if [ -z "$dev" ]; then echo "nowifi"; exit 0; fi
        p=$(iwctl device "$dev" show 2>/dev/null | strip | awk '/ Powered / { print $NF; exit }')
        echo "powered $p"
        s=$(iwctl station "$dev" show 2>/dev/null | strip \
          | awk '/Connected network/ { sub(/.*Connected network[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit }')
        echo "ssid $s"
        ;;
      list)
        [ -n "$dev" ] || exit 0
        iwctl station "$dev" scan >/dev/null 2>&1
        sleep 2
        iwctl station "$dev" get-networks rssi-dbms 2>/dev/null | strip
        echo "@@KNOWN"
        iwctl known-networks list 2>/dev/null | strip
        ;;
      connect)
        if [ -z "$dev" ]; then echo "no wifi adapter"; echo "@@FAIL"; exit 0; fi
        if [ $# -ge 3 ]; then
          out=$(timeout 30 iwctl --passphrase "$3" station "$dev" connect "$2" 2>&1 </dev/null)
        else
          out=$(timeout 30 iwctl station "$dev" connect "$2" 2>&1 </dev/null)
        fi
        code=$?
        printf '%s\n' "$out" | strip
        if [ $code -eq 0 ]; then echo "@@OK"; else echo "@@FAIL"; fi
        ;;
      disconnect)
        [ -n "$dev" ] && iwctl station "$dev" disconnect
        ;;
      forget)
        iwctl known-networks "$2" forget
        ;;
      power)
        [ -n "$dev" ] && iwctl device "$dev" set-property Powered "$2"
        ;;
    esac
  '';

in
{
  home.packages = [ quickshell ];

  # --- палитра: берётся из текущей схемы (команда `theme`), размеры ---
  xdg.configFile."quickshell/Theme.qml".text = ''
    pragma Singleton
    import Quickshell
    import Quickshell.Io
    import QtQuick

    Singleton {
        id: theme

        readonly property string cmd: "${theme.cmd}/bin/theme"
        readonly property string schemesFile: "${theme.schemes}"
        readonly property string stateDir: "${theme.stateDir}"

        // из схемы
        property string name: "oxocarbon"
        property color base: "#161616"
        property color fg: "#f2f4f8"
        property color blue: "#78a9ff"
        property color pink: "#be95ff"
        property color mint: "#08bdba"
        property string wallpaper: ""

        // производные
        readonly property color bg: Qt.rgba(base.r, base.g, base.b, 0.9)
        readonly property color bgMenu: Qt.rgba(base.r, base.g, base.b, 0.97)
        readonly property color bgHover: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.1))
        readonly property color border: Qt.tint(base, Qt.rgba(fg.r, fg.g, fg.b, 0.12))
        readonly property color track: Qt.tint(base, Qt.rgba(fg.r, fg.g, fg.b, 0.18))
        readonly property color fgDim: Qt.tint(base, Qt.rgba(fg.r, fg.g, fg.b, 0.5))
        readonly property color dark: base
        readonly property color white: fg

        readonly property string font: "FiraCode Nerd Font"
        readonly property int fontSize: 14
        readonly property int iconSize: 14
        readonly property int pillH: 38
        readonly property int radius: 12

        function reload() {
            currentFile.reload();
            wallFile.reload();
        }
        function setTheme(n) { Quickshell.execDetached([ cmd, "set", n ]); }
        function setWallpaper(path) { Quickshell.execDetached([ cmd, "wall", path ]); }

        FileView {
            id: currentFile
            path: theme.stateDir + "/current.json"
            blockLoading: true
            onLoaded: {
                try {
                    const t = JSON.parse(text());
                    theme.name = t.name;
                    theme.base = t.bg;
                    theme.fg = t.fg;
                    theme.blue = t.c[12];
                    theme.pink = t.c[13];
                    theme.mint = t.c[14];
                } catch (e) {}
            }
        }

        FileView {
            id: wallFile
            path: theme.stateDir + "/wallpaper"
            blockLoading: true
            onLoaded: theme.wallpaper = text().trim()
        }

        // `theme` дёргает это после каждой смены
        IpcHandler {
            target: "theme"
            function reload(): void { theme.reload(); }
        }
    }
  '';

  # --- wifi: состояние + команды ---
  xdg.configFile."quickshell/Net.qml".text = ''
    pragma Singleton
    import Quickshell
    import Quickshell.Io
    import QtQuick

    Singleton {
        id: net

        readonly property string wifiCmd: "${wifiScript}"

        // wifi
        property bool powered: true
        property bool hasWifi: true
        // кабель
        property bool wiredUp: false
        property string ssid: ""
        property var networks: []   // { ssid, security, signal 0..1, connected, known }
        property bool scanning: false
        property bool busy: false
        property string message: ""

        function refresh() { statusProc.running = true; }

        function scan() {
            if (scanProc.running) return;
            scanning = true;
            scanProc.running = true;
        }

        function connect(name, pass) {
            if (connectProc.running) return;
            busy = true;
            message = "connecting to " + name + "…";
            connectProc.command = pass ? [ wifiCmd, "connect", name, pass ] : [ wifiCmd, "connect", name ];
            connectProc.running = true;
        }

        function run(args) {
            actionProc.command = [ wifiCmd ].concat(args);
            actionProc.running = true;
        }
        function disconnect() { run([ "disconnect" ]); }
        function forget(name) { run([ "forget", name ]); }
        function setPowered(on) {
            powered = on;
            if (!on) networks = [];
            run([ "power", on ? "on" : "off" ]);
        }

        function parseNetworks(text) {
            const parts = text.split("@@KNOWN");
            const types = "(psk|open|8021x|wep|owe|sae)";
            const known = new Set();
            for (const line of (parts[1] || "").split("\n")) {
                const m = line.match(new RegExp("^\\s*(.+?)\\s{2,}" + types + "\\b"));
                if (m) known.add(m[1]);
            }
            const list = [];
            const seen = new Set();
            for (const line of parts[0].split("\n")) {
                const m = line.match(new RegExp("^\\s*(>\\s+)?(.+?)\\s{2,}" + types + "\\s+(\\S+)\\s*$"));
                if (!m || seen.has(m[2])) continue;
                seen.add(m[2]);
                let dbm = parseFloat(m[4]);
                if (isNaN(dbm)) dbm = -90 + 15 * (m[4].match(/\*/g) || []).length;
                else if (Math.abs(dbm) > 200) dbm = dbm / 100;
                list.push({
                    ssid: m[2],
                    security: m[3],
                    signal: Math.max(0, Math.min(1, (dbm + 90) / 60)),
                    connected: !!m[1] || m[2] === ssid,
                    known: known.has(m[2]),
                });
            }
            list.sort((a, b) => (b.connected - a.connected) || (b.signal - a.signal));
            networks = list;
        }

        Process {
            id: statusProc
            command: [ net.wifiCmd, "status" ]
            stdout: StdioCollector {
                onStreamFinished: {
                    let wifi = true, up = false;
                    for (const line of text.split("\n")) {
                        if (line.startsWith("powered ")) net.powered = line.slice(8).trim() === "on";
                        else if (line.startsWith("ssid ")) net.ssid = line.slice(5).trim();
                        else if (line.trim() === "nowifi") wifi = false;
                        else if (line.startsWith("wired ")) {
                            up = line.trim().split(/\s+/)[1] === "up";
                        }
                    }
                    net.hasWifi = wifi;
                    if (!wifi) net.ssid = "";
                    net.wiredUp = up;
                }
            }
        }

        Process {
            id: scanProc
            command: [ net.wifiCmd, "list" ]
            stdout: StdioCollector {
                onStreamFinished: {
                    net.scanning = false;
                    net.parseNetworks(text);
                }
            }
        }

        Process {
            id: connectProc
            stdout: StdioCollector {
                onStreamFinished: {
                    const out = text.trim();
                    net.busy = false;
                    if (out.endsWith("@@OK")) {
                        net.message = "";
                    } else {
                        const lines = out.replace("@@FAIL", "").trim().split("\n").filter(l => l.trim());
                        net.message = "connection failed" + (lines.length ? ": " + lines[lines.length - 1].trim().toLowerCase() : "");
                    }
                    net.refresh();
                    net.scan();
                }
            }
        }

        Process {
            id: actionProc
            onExited: (code, status) => {
                net.refresh();
                refreshLater.restart();
            }
        }

        // сеть подключается не мгновенно
        Timer {
            id: refreshLater
            interval: 1500
            onTriggered: { net.refresh(); net.scan(); }
        }

        Timer {
            interval: 10000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: net.refresh()
        }
    }
  '';

  # --- связь с mango через mmsg: теги и активный монитор ---
  xdg.configFile."quickshell/Mango.qml".text = ''
    pragma Singleton
    import Quickshell
    import Quickshell.Io
    import QtQuick

    Singleton {
        id: mango

        readonly property string mmsg: "${pkgs.mango}/bin/mmsg"

        // { "eDP-1": [ { index, is_active, is_urgent, layout, client_count }, ... ] }
        property var tags: ({})
        property string focusedMonitor: ""

        function view(index, monitor) {
            Quickshell.execDetached([ mmsg, "dispatch", "viewcrossmon," + index + "," + monitor ]);
        }

        // mmsg watch держит соединение и присылает json-строку на каждое изменение
        Process {
            id: tagsWatch
            running: true
            command: [ mango.mmsg, "watch", "all-tags" ]
            stdout: SplitParser {
                onRead: data => {
                    try {
                        const t = {};
                        for (const m of JSON.parse(data).all_tags) t[m.monitor] = m.tags;
                        mango.tags = t;
                    } catch (e) {}
                }
            }
            onExited: restart.restart()
        }

        Process {
            id: monitorsWatch
            running: true
            command: [ mango.mmsg, "watch", "all-monitors" ]
            stdout: SplitParser {
                onRead: data => {
                    try {
                        for (const m of JSON.parse(data).monitors)
                            if (m.active) mango.focusedMonitor = m.name;
                    } catch (e) {}
                }
            }
            onExited: restart.restart()
        }

        // если mango перезапустился или соединение упало - переподключиться
        Timer {
            id: restart
            interval: 2000
            onTriggered: {
                tagsWatch.running = true;
                monitorsWatch.running = true;
            }
        }
    }
  '';

  # --- плашка ---
  xdg.configFile."quickshell/Pill.qml".text = ''
    import QtQuick

    Rectangle {
        id: pill
        signal clicked(var mouse)
        signal scrolled(var event)
        readonly property bool hovered: area.containsMouse

        implicitHeight: Theme.pillH
        radius: Theme.radius
        color: hovered ? Theme.bgHover : Theme.bg
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => pill.clicked(mouse)
            onWheel: event => pill.scrolled(event)
        }
    }
  '';

  # --- текст/иконка ---
  xdg.configFile."quickshell/Glyph.qml".text = ''
    import QtQuick

    Text {
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }
  '';

  # --- круглая кнопка-иконка ---
  xdg.configFile."quickshell/IconButton.qml".text = ''
    import QtQuick

    Rectangle {
        id: btn
        property string icon
        property bool spinning: false
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        radius: 10
        color: area.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        onSpinningChanged: if (!spinning) glyph.rotation = 0

        Glyph {
            id: glyph
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: 15
            RotationAnimation on rotation {
                running: btn.spinning
                from: 0; to: 360; duration: 900
                loops: Animation.Infinite
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
  '';

  # --- переключатель ---
  xdg.configFile."quickshell/Toggle.qml".text = ''
    import QtQuick

    Rectangle {
        id: t
        property bool checked: false
        signal toggled()

        implicitWidth: 44
        implicitHeight: 24
        radius: 12
        opacity: enabled ? 1 : 0.5
        color: checked ? Theme.blue : Theme.track
        Behavior on color { ColorAnimation { duration: 160 } }

        Rectangle {
            width: 18; height: 18; radius: 9
            y: 3
            x: t.checked ? t.width - width - 3 : 3
            color: t.checked ? Theme.dark : Theme.fg
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: t.toggled()
        }
    }
  '';

  # --- меню wifi ---
  xdg.configFile."quickshell/WifiMenu.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: menu
        property var barWindow
        property bool open: false
        property int leftOffset: 12
        property string selected: ""   // сеть, для которой открыт ввод пароля

        // окно на весь экран: клик мимо меню его закрывает
        visible: open
        screen: barWindow.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-wifi"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        onOpenChanged: {
            if (!open) return;
            selected = "";
            Net.message = "";
            Net.refresh();
            Net.scan();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: menu.open = false
        }

        Rectangle {
            x: menu.leftOffset
            y: Theme.pillH + 18
            width: 390
            height: content.implicitHeight + 32
            radius: 16
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            // клики внутри меню не закрывают его
            MouseArea { anchors.fill: parent }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: menu.open = false
            }

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 10

                // ---------- заголовок ----------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Glyph { text: ""; color: Theme.blue; font.pixelSize: 16 }
                    Glyph { text: "wi-fi"; font.pixelSize: 16; Layout.fillWidth: true }
                    IconButton {
                        icon: ""
                        visible: Net.powered
                        spinning: Net.scanning
                        onClicked: Net.scan()
                    }
                    Toggle {
                        checked: Net.powered
                        onToggled: Net.setPowered(!Net.powered)
                    }
                }

                // ---------- список сетей ----------
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 320)
                    visible: Net.powered && count > 0
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: menu.open && Net.powered ? Net.networks : []

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool expanded: menu.selected === modelData.ssid
                        property bool showPass: false

                        width: ListView.view.width
                        height: col.implicitHeight
                        radius: 11
                        color: rowArea.containsMouse || expanded ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        function submit() {
                            if (!pass.text) return;
                            Net.connect(modelData.ssid, pass.text);
                            menu.selected = "";
                        }

                        onExpandedChanged: {
                            if (!expanded) return;
                            pass.text = "";
                            showPass = false;
                            pass.forceActiveFocus();
                        }

                        ColumnLayout {
                            id: col
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            spacing: 0

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 46

                                // лкм: подключиться / отключиться, пкм: забыть сеть
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        const n = row.modelData;
                                        if (mouse.button === Qt.RightButton) {
                                            if (n.known) Net.forget(n.ssid);
                                        } else if (n.connected) {
                                            Net.disconnect();
                                        } else if (n.known || n.security === "open") {
                                            menu.selected = "";
                                            Net.connect(n.ssid, "");
                                        } else {
                                            menu.selected = row.expanded ? "" : n.ssid;
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12

                                    Glyph {
                                        text: ""
                                        font.pixelSize: 14
                                        color: row.modelData.connected ? Theme.blue : Theme.fg
                                        opacity: 0.3 + 0.7 * row.modelData.signal
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Glyph {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: row.modelData.ssid
                                            color: row.modelData.connected ? Theme.blue : Theme.fg
                                        }
                                        Glyph {
                                            visible: row.modelData.connected || row.modelData.known
                                            text: row.modelData.connected
                                                ? (rowArea.containsMouse ? "click to disconnect" : "connected")
                                                : "saved · right-click to forget"
                                            color: Theme.fgDim
                                            font.pixelSize: 11
                                            font.bold: false
                                        }
                                    }
                                    Glyph {
                                        visible: row.modelData.security !== "open"
                                        text: ""
                                        font.pixelSize: 12
                                        color: Theme.fgDim
                                    }
                                    Glyph {
                                        visible: row.modelData.connected
                                        text: ""
                                        font.pixelSize: 13
                                        color: Theme.mint
                                    }
                                }
                            }

                            // ввод пароля
                            RowLayout {
                                visible: row.expanded
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                Layout.bottomMargin: 10
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: 9
                                    color: Theme.bg
                                    border.width: 1
                                    border.color: pass.activeFocus ? Theme.blue : Theme.border

                                    TextInput {
                                        id: pass
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.fg
                                        selectionColor: Theme.blue
                                        selectedTextColor: Theme.dark
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        echoMode: row.showPass ? TextInput.Normal : TextInput.Password
                                        selectByMouse: true
                                        clip: true
                                        onAccepted: row.submit()
                                        Keys.onEscapePressed: menu.selected = ""

                                        Glyph {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !pass.text
                                            text: "password"
                                            color: Theme.fgDim
                                            font.bold: false
                                        }
                                    }
                                }
                                IconButton {
                                    icon: row.showPass ? "" : ""
                                    onClicked: row.showPass = !row.showPass
                                }
                                IconButton {
                                    icon: ""
                                    onClicked: row.submit()
                                }
                            }
                        }
                    }
                }

                Glyph {
                    visible: !Net.powered || list.count === 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 6
                    bottomPadding: 6
                    text: !Net.powered ? "wi-fi is off" : Net.scanning ? "scanning…" : "no networks found"
                    color: Theme.fgDim
                    font.bold: false
                }

                Glyph {
                    visible: Net.message !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Net.message
                    color: Net.busy ? Theme.fgDim : Theme.pink
                    font.pixelSize: 12
                    font.bold: false
                }

            }
        }
    }
  '';

  # --- лаунчер приложений (вместо rofi), шапка как у часов ---
  xdg.configFile."quickshell/Launcher.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import Quickshell.Widgets
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: launcher
        property bool open: false
        property string query: ""
        property int current: 0
        readonly property int rowH: 54
        readonly property int maxRows: 7

        readonly property var apps: {
            if (!open) return [];
            const q = query.trim().toLowerCase();
            const found = [];
            for (const a of DesktopEntries.applications.values) {
                if (a.noDisplay) continue;
                const name = (a.name || "").toLowerCase();
                const extra = [ a.genericName || "", a.comment || "", (a.keywords || []).join(" ") ]
                    .join(" ").toLowerCase();
                let score = -1;
                if (!q) score = 0;
                else if (name.startsWith(q)) score = 3;
                else if (name.includes(q)) score = 2;
                else if (extra.includes(q)) score = 1;
                if (score >= 0) found.push({ entry: a, score: score, name: name });
            }
            found.sort((x, y) => (y.score - x.score) || x.name.localeCompare(y.name));
            return found.map(f => f.entry);
        }

        function toggle() {
            if (open) { open = false; return; }
            const s = Quickshell.screens.find(x => x.name === Mango.focusedMonitor);
            if (s) screen = s;
            input.text = "";
            current = 0;
            open = true;
            input.forceActiveFocus();
        }

        function launch(entry) {
            if (!entry) return;
            entry.execute();
            open = false;
        }

        // окно на весь экран с лёгким затемнением: клик мимо закрывает
        visible: open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-launcher"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#33000000"

        MouseArea {
            anchors.fill: parent
            onClicked: launcher.open = false
        }

        Rectangle {
            id: box
            width: 580
            height: col.implicitHeight + 28
            x: Math.round((parent.width - width) / 2)
            y: Math.round(parent.height * 0.18)
            radius: 18
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // поиск: градиент как у часов
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.white }
                        GradientStop { position: 0.6; color: Theme.white }
                        GradientStop { position: 1.0; color: Theme.pink }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14

                        Glyph { text: ""; color: Theme.dark; font.pixelSize: 16 }

                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            color: Theme.dark
                            selectionColor: Theme.blue
                            selectedTextColor: Theme.dark
                            font.family: Theme.font
                            font.pixelSize: 17
                            font.bold: true
                            clip: true
                            focus: true

                            onTextChanged: {
                                launcher.query = text;
                                launcher.current = 0;
                            }

                            Keys.onPressed: event => {
                                const n = launcher.apps.length;
                                if (event.key === Qt.Key_Escape) {
                                    launcher.open = false;
                                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                    launcher.current = Math.min(launcher.current + 1, n - 1);
                                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                                    launcher.current = Math.max(launcher.current - 1, 0);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    launcher.launch(launcher.apps[launcher.current]);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !input.text
                                text: "search apps…"
                                color: "#8e879c"
                                font.pixelSize: 17
                            }
                        }

                        Glyph { text: ""; color: Theme.dark; font.pixelSize: 18 }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, launcher.maxRows) * (launcher.rowH + spacing)
                    visible: count > 0
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: launcher.apps
                    currentIndex: launcher.current
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: item
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === launcher.current

                        width: ListView.view.width
                        height: launcher.rowH
                        radius: 12
                        color: selected ? Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // полоска слева у выбранного
                        Rectangle {
                            visible: item.selected
                            width: 4; height: 24; radius: 2
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Theme.pink }
                                GradientStop { position: 1.0; color: Theme.blue }
                            }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 18; rightMargin: 14 }
                            spacing: 14

                            IconImage {
                                implicitSize: 32
                                asynchronous: true
                                source: Quickshell.iconPath(item.modelData.icon, "application-x-executable")
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Glyph {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: item.modelData.name
                                    color: item.selected ? Theme.white : Theme.fg
                                }
                                Glyph {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                    text: item.modelData.genericName || item.modelData.comment || ""
                                    color: Theme.fgDim
                                    font.pixelSize: 11
                                    font.bold: false
                                }
                            }
                            Glyph {
                                visible: item.selected
                                text: ""
                                color: Theme.pink
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.current = item.index
                            onClicked: launcher.launch(item.modelData)
                        }
                    }
                }

                Glyph {
                    visible: list.count === 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 8
                    bottomPadding: 8
                    text: "nothing found"
                    color: Theme.fgDim
                    font.bold: false
                }
            }
        }
    }
  '';

  # --- обои: рисует сам quickshell, плавная смена без перезапуска ---
  xdg.configFile."quickshell/Wallpaper.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import QtQuick

    PanelWindow {
        id: w
        property string current: ""
        readonly property string target: Theme.wallpaper

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell-wallpaper"
        color: Theme.base

        function show() {
            if (!target || target === current) return;
            prev.source = img.source;
            prev.opacity = 1;
            current = target;
            img.source = "file://" + target;
        }
        onTargetChanged: show()
        Component.onCompleted: show()

        // картинка декодируется в размер экрана, а не в полный размер файла
        Image {
            id: img
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: w.screen?.width ?? 1920
            sourceSize.height: w.screen?.height ?? 1080
            onStatusChanged: if (status === Image.Ready || status === Image.Error) fade.restart()
        }

        // старые обои плавно исчезают поверх новых
        Image {
            id: prev
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            cache: false
            sourceSize.width: w.screen?.width ?? 1920
            sourceSize.height: w.screen?.height ?? 1080

            NumberAnimation on opacity {
                id: fade
                running: false
                to: 0
                duration: 700
                easing.type: Easing.InOutQuad
                onFinished: prev.source = ""
            }
        }
    }
  '';

  # --- выбор темы и обоев ---
  xdg.configFile."quickshell/StylePanel.qml".text = ''
    import Quickshell
    import Quickshell.Io
    import Quickshell.Wayland
    import Quickshell.Widgets
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: panel
        property bool open: false
        property int tab: 0          // 0 - темы, 1 - обои
        property var schemes: []
        property var walls: []

        function toggle(which) {
            if (open && which === tab) { open = false; return; }
            tab = which;
            if (!open) {
                const s = Quickshell.screens.find(x => x.name === Mango.focusedMonitor);
                if (s) screen = s;
                open = true;
            }
            wallsProc.running = true;
        }

        // окно на весь экран с лёгким затемнением: клик мимо закрывает
        visible: open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-style"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#33000000"

        MouseArea {
            anchors.fill: parent
            onClicked: panel.open = false
        }

        FileView {
            path: Theme.schemesFile
            blockLoading: true
            onLoaded: {
                const all = JSON.parse(text());
                panel.schemes = Object.keys(all).sort().map(k => Object.assign({ name: k }, all[k]));
            }
        }

        Process {
            id: wallsProc
            command: [ Theme.cmd, "walls" ]
            stdout: StdioCollector {
                onStreamFinished: panel.walls = text.split("\n").filter(l => l.length > 0)
            }
        }

        Rectangle {
            id: box
            width: 820
            height: col.implicitHeight + 32
            x: Math.round((parent.width - width) / 2)
            y: Math.round(parent.height * 0.12)
            radius: 18
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            MouseArea { anchors.fill: parent }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: panel.open = false
                Keys.onTabPressed: panel.tab = 1 - panel.tab
            }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 14

                // вкладки
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [ { icon: "", label: "themes" }, { icon: "", label: "wallpapers" } ]

                        Rectangle {
                            id: tabBtn
                            required property var modelData
                            required property int index
                            readonly property bool active: panel.tab === index

                            implicitWidth: tabRow.implicitWidth + 32
                            implicitHeight: 40
                            radius: 12
                            color: active ? Theme.fg : (tabArea.containsMouse ? Theme.bgHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }

                            RowLayout {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 10
                                Glyph {
                                    text: tabBtn.modelData.icon
                                    color: tabBtn.active ? Theme.base : Theme.pink
                                    font.pixelSize: 14
                                }
                                Glyph {
                                    text: tabBtn.modelData.label
                                    color: tabBtn.active ? Theme.base : Theme.fg
                                }
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.tab = tabBtn.index
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Glyph {
                        text: panel.tab === 0 ? Theme.name : panel.walls.length + " in ~/images"
                        color: Theme.fgDim
                        font.bold: false
                    }
                }

                // содержимое создаётся только пока панель открыта
                Loader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 460
                    active: panel.open
                    sourceComponent: panel.tab === 0 ? themesView : wallsView
                }
            }
        }

        Component {
            id: themesView

            GridView {
                clip: true
                cellWidth: width / 4
                cellHeight: 108
                boundsBehavior: Flickable.StopAtBounds
                model: panel.schemes

                delegate: Item {
                    id: card
                    required property var modelData
                    readonly property bool current: Theme.name === modelData.name
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight

                    Rectangle {
                        anchors { fill: parent; margins: 5 }
                        radius: 14
                        color: card.modelData.bg
                        border.width: card.current ? 2 : 1
                        border.color: card.current ? card.modelData.c[12] : Qt.rgba(0.5, 0.5, 0.5, 0.25)
                        scale: cardArea.containsMouse ? 1.03 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors { fill: parent; margins: 12 }
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Glyph {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: card.modelData.name
                                    color: card.modelData.fg
                                    font.pixelSize: 13
                                }
                                Glyph {
                                    visible: card.current
                                    text: ""
                                    color: card.modelData.c[10]
                                    font.pixelSize: 12
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // 7 основных цветов
                            RowLayout {
                                spacing: 5
                                Repeater {
                                    model: 7
                                    Rectangle {
                                        required property int index
                                        implicitWidth: 14
                                        implicitHeight: 14
                                        radius: 7
                                        color: card.modelData.c[index + 9]
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setTheme(card.modelData.name)
                        }
                    }
                }
            }
        }

        Component {
            id: wallsView

            Item {
                GridView {
                    id: grid
                    anchors.fill: parent
                    visible: count > 0
                    clip: true
                    cellWidth: width / 3
                    cellHeight: Math.round(cellWidth * 0.62)
                    boundsBehavior: Flickable.StopAtBounds
                    model: panel.walls

                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property bool current: Theme.wallpaper === modelData
                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight

                        ClippingRectangle {
                            anchors { fill: parent; margins: 6 }
                            radius: 14
                            color: Theme.bg

                            // маленькие превью, чтобы не тратить память
                            Image {
                                anchors.fill: parent
                                source: "file://" + cell.modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 320
                                sourceSize.height: 200
                            }
                        }

                        Rectangle {
                            anchors { fill: parent; margins: 6 }
                            radius: 14
                            color: "transparent"
                            border.width: cell.current ? 3 : (wallArea.containsMouse ? 2 : 0)
                            border.color: cell.current ? Theme.pink : Theme.fg
                        }

                        MouseArea {
                            id: wallArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setWallpaper(cell.modelData)
                        }
                    }
                }

                Glyph {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: "put some images into ~/images"
                    color: Theme.fgDim
                    font.bold: false
                }
            }
        }
    }
  '';

  # --- уведомления: сервер + всплывающие плашки справа ---
  xdg.configFile."quickshell/Notifications.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import Quickshell.Widgets
    import Quickshell.Services.Notifications
    import QtQuick
    import QtQuick.Layouts

    Scope {
        id: root

        NotificationServer {
            id: server
            keepOnReload: true
            bodySupported: true
            bodyMarkupSupported: false
            actionsSupported: true
            imageSupported: true
            onNotification: n => { n.tracked = true; }
        }

        PanelWindow {
            id: popups
            readonly property var items: server.trackedNotifications.values.slice(-5).reverse()

            visible: items.length > 0
            anchors { top: true; right: true }
            margins { top: Theme.pillH + 18; right: 12 }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-notifications"
            implicitWidth: 390
            implicitHeight: Math.max(1, stack.implicitHeight)
            color: "transparent"

            ColumnLayout {
                id: stack
                width: parent.width
                spacing: 8

                Repeater {
                    model: popups.items

                    Rectangle {
                        id: card
                        required property var modelData
                        readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                        readonly property var actionList: {
                            const a = [];
                            const l = modelData.actions;
                            for (let i = 0; i < l.length; i++) a.push(l[i]);
                            return a;
                        }
                        readonly property string icon: {
                            if (modelData.image) return modelData.image;
                            if (modelData.appIcon) return Quickshell.iconPath(modelData.appIcon, true);
                            return "";
                        }

                        Layout.fillWidth: true
                        implicitHeight: body.implicitHeight + 28
                        radius: 14
                        color: area.containsMouse ? Qt.tint(Theme.bgMenu, Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)) : Theme.bgMenu
                        border.width: 1
                        border.color: critical ? Theme.pink : Theme.border

                        opacity: 0
                        Component.onCompleted: opacity = 1
                        Behavior on opacity { NumberAnimation { duration: 180 } }

                        // висит 6 секунд (под мышкой - не пропадает), важные - пока не закроешь
                        Timer {
                            interval: 6000
                            running: !card.critical && !area.containsMouse
                            onTriggered: card.modelData.expire()
                        }

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                const n = card.modelData;
                                const def = card.actionList.find(a => a.identifier === "default");
                                if (mouse.button === Qt.LeftButton && def) def.invoke();
                                else n.dismiss();
                            }
                        }

                        RowLayout {
                            id: body
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 12

                            ClippingRectangle {
                                visible: card.icon !== ""
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 42
                                implicitHeight: 42
                                radius: 10
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: card.icon
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 84
                                    sourceSize.height: 84
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    Glyph {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: card.modelData.appName || "notification"
                                        color: card.critical ? Theme.pink : Theme.fgDim
                                        font.pixelSize: 11
                                        font.bold: false
                                    }
                                    Glyph {
                                        text: ""
                                        color: closeArea.containsMouse ? Theme.fg : Theme.fgDim
                                        font.pixelSize: 11
                                        MouseArea {
                                            id: closeArea
                                            anchors { fill: parent; margins: -6 }
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: card.modelData.dismiss()
                                        }
                                    }
                                }
                                Glyph {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: card.modelData.summary
                                }
                                Glyph {
                                    visible: text !== ""
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: card.modelData.body
                                    color: Theme.fgDim
                                    font.pixelSize: 12
                                    font.bold: false
                                }

                                // кнопки действий (кроме действия по умолчанию)
                                RowLayout {
                                    visible: actionsRepeater.count > 0
                                    Layout.topMargin: 4
                                    spacing: 6
                                    Repeater {
                                        id: actionsRepeater
                                        model: card.actionList.filter(a => a.identifier !== "default")
                                        Rectangle {
                                            id: actionBtn
                                            required property var modelData
                                            implicitWidth: actionText.implicitWidth + 20
                                            implicitHeight: 28
                                            radius: 8
                                            color: actionArea.containsMouse ? Theme.bgHover : Theme.track
                                            Glyph {
                                                id: actionText
                                                anchors.centerIn: parent
                                                text: actionBtn.modelData.text
                                                font.pixelSize: 12
                                            }
                                            MouseArea {
                                                id: actionArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: actionBtn.modelData.invoke()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
  '';

  # --- всплывающий индикатор громкости и яркости ---
  xdg.configFile."quickshell/Osd.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import Quickshell.Services.Pipewire
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: osd
        property string kind: "volume"
        property real value: 0
        property bool muted: false

        readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
        // первые секунды после запуска pipewire сам "меняет" громкость - не показываем
        property bool armed: false

        function show(k, v, m) {
            kind = k;
            value = Math.max(0, Math.min(1, v));
            muted = m;
            visible = true;
            hideTimer.restart();
        }

        visible: false
        anchors.bottom: true
        margins.bottom: 90
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-osd"
        implicitWidth: 320
        implicitHeight: 56
        color: "transparent"

        Timer { interval: 3000; running: true; onTriggered: osd.armed = true }
        Timer { id: hideTimer; interval: 1400; onTriggered: osd.visible = false }

        Connections {
            target: osd.audio
            function onVolumeChanged() { if (osd.armed) osd.show("volume", osd.audio.volume, osd.audio.muted); }
            function onMutedChanged() { if (osd.armed) osd.show("volume", osd.audio.volume, osd.audio.muted); }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            RowLayout {
                anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                spacing: 14

                Glyph {
                    Layout.preferredWidth: 20
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 16
                    color: Theme.pink
                    text: osd.kind === "brightness" ? ""
                        : osd.muted ? "" : osd.value > 0.5 ? "" : ""
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: Theme.track

                    Rectangle {
                        width: parent.width * (osd.muted ? 0 : osd.value)
                        height: parent.height
                        radius: 4
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.blue }
                            GradientStop { position: 1.0; color: Theme.pink }
                        }
                    }
                }

                Glyph {
                    Layout.preferredWidth: 42
                    horizontalAlignment: Text.AlignRight
                    text: osd.muted ? "mute" : Math.round(osd.value * 100) + "%"
                }
            }
        }
    }
  '';

  # --- история буфера обмена (cliphist) ---
  xdg.configFile."quickshell/ClipMenu.qml".text = ''
    import Quickshell
    import Quickshell.Io
    import Quickshell.Wayland
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: clipMenu
        property bool open: false
        property var entries: []     // строки cliphist: "id<tab>текст"
        property string query: ""
        property int current: 0
        readonly property int rowH: 44

        readonly property var shown: {
            if (!open) return [];
            const q = query.trim().toLowerCase();
            return entries.filter(e => !q || e.toLowerCase().includes(q));
        }

        function toggle() {
            if (open) { open = false; return; }
            const s = Quickshell.screens.find(x => x.name === Mango.focusedMonitor);
            if (s) screen = s;
            input.text = "";
            current = 0;
            entries = [];
            listProc.running = true;
            open = true;
            input.forceActiveFocus();
        }
        function preview(line) { return line.slice(line.indexOf("\t") + 1); }
        function pick(line) {
            if (!line) return;
            Quickshell.execDetached([ "clip", "copy", line ]);
            open = false;
        }
        function remove(line) {
            if (!line) return;
            Quickshell.execDetached([ "clip", "delete", line ]);
            entries = entries.filter(e => e !== line);
        }

        Process {
            id: listProc
            command: [ "clip", "list" ]
            stdout: StdioCollector {
                onStreamFinished: clipMenu.entries = text.split("\n").filter(l => l.length > 0)
            }
        }

        visible: open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-clipboard"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#33000000"

        MouseArea {
            anchors.fill: parent
            onClicked: clipMenu.open = false
        }

        Rectangle {
            id: box
            width: 640
            height: col.implicitHeight + 28
            x: Math.round((parent.width - width) / 2)
            y: Math.round(parent.height * 0.16)
            radius: 18
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // поиск: градиент как у часов
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.white }
                        GradientStop { position: 0.6; color: Theme.white }
                        GradientStop { position: 1.0; color: Theme.pink }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14

                        Glyph { text: ""; color: Theme.dark; font.pixelSize: 16 }

                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            color: Theme.dark
                            selectionColor: Theme.blue
                            selectedTextColor: Theme.dark
                            font.family: Theme.font
                            font.pixelSize: 17
                            font.bold: true
                            clip: true
                            focus: true

                            onTextChanged: {
                                clipMenu.query = text;
                                clipMenu.current = 0;
                            }

                            Keys.onPressed: event => {
                                const n = clipMenu.shown.length;
                                if (event.key === Qt.Key_Escape) {
                                    clipMenu.open = false;
                                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                    clipMenu.current = Math.min(clipMenu.current + 1, n - 1);
                                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                                    clipMenu.current = Math.max(clipMenu.current - 1, 0);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    clipMenu.pick(clipMenu.shown[clipMenu.current]);
                                } else if (event.key === Qt.Key_Delete) {
                                    clipMenu.remove(clipMenu.shown[clipMenu.current]);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !input.text
                                text: "search clipboard… (delete to remove)"
                                color: "#8e879c"
                                font.pixelSize: 17
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, 8) * (clipMenu.rowH + spacing)
                    visible: count > 0
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: clipMenu.shown
                    currentIndex: clipMenu.current
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === clipMenu.current

                        width: ListView.view.width
                        height: clipMenu.rowH
                        radius: 12
                        color: selected ? Theme.bgHover : "transparent"

                        Rectangle {
                            visible: row.selected
                            width: 4; height: 22; radius: 2
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Theme.pink }
                                GradientStop { position: 1.0; color: Theme.blue }
                            }
                        }

                        Glyph {
                            anchors { fill: parent; leftMargin: 18; rightMargin: 14 }
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: clipMenu.preview(row.modelData).replace(/\s+/g, " ")
                            color: row.selected ? Theme.white : Theme.fg
                            font.bold: false
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: clipMenu.current = row.index
                            onClicked: clipMenu.pick(row.modelData)
                        }
                    }
                }

                Glyph {
                    visible: list.count === 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 8
                    bottomPadding: 8
                    text: listProc.running ? "loading…" : "clipboard is empty"
                    color: Theme.fgDim
                    font.bold: false
                }
            }
        }
    }
  '';

  # --- меню питания ---
  xdg.configFile."quickshell/PowerMenu.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: power
        property bool open: false
        property int current: 0

        readonly property var actions: [
            { icon: "", label: "lock", cmd: [ "lock" ] },
            { icon: "", label: "sleep", cmd: [ "systemctl", "suspend" ] },
            { icon: "", label: "log out", cmd: [ Mango.mmsg, "dispatch", "quit" ] },
            { icon: "", label: "reboot", cmd: [ "systemctl", "reboot" ] },
            { icon: "", label: "shut down", cmd: [ "systemctl", "poweroff" ] }
        ]

        function toggle() {
            if (open) { open = false; return; }
            const s = Quickshell.screens.find(x => x.name === Mango.focusedMonitor);
            if (s) screen = s;
            current = 0;
            open = true;
            keys.forceActiveFocus();
        }
        function run(i) {
            open = false;
            Quickshell.execDetached(actions[i].cmd);
        }

        visible: open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-power"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#55000000"

        MouseArea {
            anchors.fill: parent
            onClicked: power.open = false
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                const n = power.actions.length;
                if (event.key === Qt.Key_Escape) power.open = false;
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) power.current = (power.current + n - 1) % n;
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) power.current = (power.current + 1) % n;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) power.run(power.current);
                else return;
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: row.implicitWidth + 32
            height: row.implicitHeight + 32
            radius: 22
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            MouseArea { anchors.fill: parent }

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: 12

                Repeater {
                    model: power.actions

                    Rectangle {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property bool selected: power.current === index

                        implicitWidth: 112
                        implicitHeight: 112
                        radius: 18
                        color: selected ? Theme.fg : Theme.bgHover
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            Glyph {
                                Layout.alignment: Qt.AlignHCenter
                                text: btn.modelData.icon
                                font.pixelSize: 30
                                color: btn.selected ? Theme.base : Theme.pink
                            }
                            Glyph {
                                Layout.alignment: Qt.AlignHCenter
                                text: btn.modelData.label
                                font.pixelSize: 12
                                color: btn.selected ? Theme.base : Theme.fg
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: power.current = btn.index
                            onClicked: power.run(btn.index)
                        }
                    }
                }
            }
        }
    }
  '';

  # --- ползунок громкости для узла pipewire: клик по иконке - mute, тянуть/колесо - громкость ---
  xdg.configFile."quickshell/VolumeSlider.qml".text = ''
    import QtQuick
    import QtQuick.Layouts

    RowLayout {
        id: s
        property var node: null
        property string icon: ""
        property string mutedIcon: "󰖁"
        property color accent: Theme.blue

        readonly property var audio: node?.audio ?? null
        readonly property bool muted: audio?.muted ?? false
        readonly property real value: Math.max(0, Math.min(1, audio?.volume ?? 0))

        spacing: 8
        opacity: audio ? 1 : 0.5

        function setFrom(x, w) {
            if (!audio) return;
            audio.volume = Math.max(0, Math.min(1, x / w));
            if (audio.muted) audio.muted = false;
        }

        IconButton {
            icon: s.muted ? s.mutedIcon : s.icon
            onClicked: if (s.audio) s.audio.muted = !s.audio.muted
        }

        Item {
            id: area
            Layout.fillWidth: true
            implicitHeight: 28

            Rectangle {
                id: track
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 8
                radius: 4
                color: Theme.track

                Rectangle {
                    width: parent.width * s.value
                    height: parent.height
                    radius: 4
                    color: s.muted ? Theme.fgDim : s.accent
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on width {
                        enabled: !drag.pressed
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }
            }

            // ручка
            Rectangle {
                width: drag.pressed || drag.containsMouse ? 18 : 14
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(area.width - width, area.width * s.value - width / 2))
                color: Theme.fg
                border.width: 3
                border.color: s.muted ? Theme.fgDim : s.accent
                Behavior on width { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => s.setFrom(mouse.x, width)
                onPositionChanged: mouse => { if (pressed) s.setFrom(mouse.x, width); }
                onWheel: event => {
                    if (!s.audio) return;
                    const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
                    s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + step));
                }
            }
        }

        Glyph {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: s.muted ? "mute" : Math.round(s.value * 100) + "%"
            color: s.muted ? Theme.fgDim : Theme.fg
            font.pixelSize: 12
        }
    }
  '';

  # --- строка устройства в меню звука: клик - сделать устройством по умолчанию ---
  xdg.configFile."quickshell/AudioDevice.qml".text = ''
    import QtQuick
    import QtQuick.Layouts

    Rectangle {
        id: row
        property var node: null
        property bool current: false
        property string icon: "󰓃"
        signal picked()

        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: current ? Qt.tint(Theme.bg, Qt.rgba(Theme.blue.r, Theme.blue.g, Theme.blue.b, 0.14))
            : area.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12

            Glyph {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: row.icon
                font.pixelSize: 15
                color: row.current ? Theme.blue : Theme.fgDim
            }
            Glyph {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: (row.node?.description || row.node?.nickname || row.node?.name || "").toLowerCase()
                color: row.current ? Theme.blue : Theme.fg
                font.bold: row.current
            }
            Glyph {
                visible: row.current
                text: ""
                font.pixelSize: 13
                color: Theme.mint
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!row.current) row.picked()
        }
    }
  '';

  # --- меню звука: громкость, выбор колонок/наушников, микрофон, громкость приложений ---
  xdg.configFile."quickshell/AudioMenu.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import Quickshell.Services.Pipewire
    import QtQuick
    import QtQuick.Layouts

    PanelWindow {
        id: menu
        property var barWindow
        property bool open: false
        property int leftOffset: 12
        readonly property int menuWidth: 400

        readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio !== null)
        readonly property var sinks: nodes.filter(n => n.isSink && !n.isStream)
        readonly property var sources: nodes.filter(n => !n.isSink && !n.isStream)
        // приложения, которые сейчас играют звук
        readonly property var streams: nodes.filter(n => n.isStream && !n.isSink)

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource

        function deviceIcon(n) {
            const name = (n?.name || "").toLowerCase();
            const desc = (n?.description || "").toLowerCase();
            if (name.indexOf("hdmi") >= 0 || desc.indexOf("hdmi") >= 0 || desc.indexOf("displayport") >= 0)
                return "󰍹";   // монитор
            if (name.indexOf("headphone") >= 0 || name.indexOf("headset") >= 0 || desc.indexOf("headphone") >= 0
                || name.indexOf("bluez") >= 0)
                return "";         // наушники
            return "󰓃";       // колонки
        }

        function appName(n) {
            const p = n?.properties ?? {};
            return (p["application.name"] || n?.description || n?.name || "app").toLowerCase();
        }

        // громкость/mute обновляются только у отслеживаемых узлов
        PwObjectTracker { objects: menu.open ? Pipewire.nodes.values : [] }

        visible: open
        screen: barWindow.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-audio"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: menu.open = false
        }

        Rectangle {
            x: menu.leftOffset
            y: Theme.pillH + 18
            width: menu.menuWidth
            height: content.implicitHeight + 32
            radius: 16
            color: Theme.bgMenu
            border.color: Theme.border
            border.width: 1

            MouseArea { anchors.fill: parent }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: menu.open = false
            }

            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 8

                // ---------- заголовок ----------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Glyph { text: ""; color: Theme.blue; font.pixelSize: 16 }
                    Glyph { text: "sound"; font.pixelSize: 16; Layout.fillWidth: true }
                    // полный микшер
                    IconButton {
                        icon: ""
                        onClicked: {
                            menu.open = false;
                            Quickshell.execDetached([ "pavucontrol" ]);
                        }
                    }
                }

                // ---------- вывод ----------
                Glyph { text: "output"; color: Theme.fgDim; font.pixelSize: 11; Layout.topMargin: 4 }
                VolumeSlider {
                    Layout.fillWidth: true
                    node: menu.sink
                    icon: menu.deviceIcon(menu.sink)
                }
                Repeater {
                    model: menu.sinks
                    AudioDevice {
                        required property var modelData
                        node: modelData
                        icon: menu.deviceIcon(modelData)
                        current: menu.sink !== null && modelData.id === menu.sink.id
                        onPicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                // ---------- микрофон ----------
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; implicitHeight: 1; color: Theme.border; visible: menu.sources.length > 0 }
                Glyph { text: "microphone"; color: Theme.fgDim; font.pixelSize: 11; visible: menu.sources.length > 0 }
                VolumeSlider {
                    Layout.fillWidth: true
                    visible: menu.source !== null
                    node: menu.source
                    icon: ""
                    mutedIcon: ""
                    accent: Theme.pink
                }
                Repeater {
                    // выбор микрофона нужен, только если их больше одного
                    model: menu.sources.length > 1 ? menu.sources : []
                    AudioDevice {
                        required property var modelData
                        node: modelData
                        icon: ""
                        current: menu.source !== null && modelData.id === menu.source.id
                        onPicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }

                // ---------- приложения ----------
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; implicitHeight: 1; color: Theme.border; visible: menu.streams.length > 0 }
                Glyph { text: "apps"; color: Theme.fgDim; font.pixelSize: 11; visible: menu.streams.length > 0 }
                Repeater {
                    model: menu.streams
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Glyph {
                            Layout.fillWidth: true
                            Layout.leftMargin: 42
                            elide: Text.ElideRight
                            text: menu.appName(modelData)
                            font.pixelSize: 12
                        }
                        VolumeSlider {
                            Layout.fillWidth: true
                            node: modelData
                            icon: ""
                            accent: Theme.mint
                        }
                    }
                }
            }
        }
    }
  '';

  xdg.configFile."quickshell/shell.qml".text = ''
    import Quickshell
    import Quickshell.Io
    import Quickshell.Widgets
    import Quickshell.Services.Pipewire
    import Quickshell.Services.UPower
    import Quickshell.Services.Mpris
    import Quickshell.Services.SystemTray
    import QtQuick
    import QtQuick.Layouts

    ShellRoot {
        id: root

        PwObjectTracker { objects: [ Pipewire.defaultAudioSink, Pipewire.defaultAudioSource ] }

        SystemClock { id: clock; precision: SystemClock.Minutes }

        // лаунчер: клик по логотипу или `qs ipc call launcher toggle`
        Launcher { id: launcher }
        IpcHandler {
            target: "launcher"
            function toggle(): void { launcher.toggle(); }
        }

        // темы и обои: кисточка на баре, `qs ipc call style themes` / `walls`
        // уведомления (сервер + плашки) и индикатор громкости/яркости
        Notifications {}
        Osd { id: osd }
        IpcHandler {
            target: "osd"
            function brightness(percent: int): void { osd.show("brightness", percent / 100, false); }
        }

        // история буфера: Alt+V
        ClipMenu { id: clipMenu }
        IpcHandler {
            target: "clipboard"
            function toggle(): void { clipMenu.toggle(); }
        }

        // меню питания: пкм по логотипу или Alt+Escape
        PowerMenu { id: powerMenu }
        IpcHandler {
            target: "power"
            function toggle(): void { powerMenu.toggle(); }
        }

        StylePanel { id: stylePanel }
        IpcHandler {
            target: "style"
            function themes(): void { stylePanel.toggle(0); }
            function walls(): void { stylePanel.toggle(1); }
        }

        // обои на каждом мониторе
        Variants {
            model: Quickshell.screens
            Wallpaper {
                required property var modelData
                screen: modelData
            }
        }

        // --- загрузка cpu для квадратиков ---
        property var cpuPrev: [ 0, 0 ]
        property real cpu: 0
        Process {
            id: cpuProc
            command: [ "head", "-n1", "/proc/stat" ]
            stdout: StdioCollector {
                onStreamFinished: {
                    const f = text.trim().split(/\s+/).slice(1).map(Number);
                    const idle = f[3] + (f[4] || 0);
                    const total = f.reduce((a, b) => a + b, 0);
                    const dt = total - root.cpuPrev[0];
                    if (root.cpuPrev[0] > 0 && dt > 0)
                        root.cpu = 1 - (idle - root.cpuPrev[1]) / dt;
                    root.cpuPrev = [ total, idle ];
                }
            }
        }
        Timer {
            interval: 2000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: cpuProc.running = true
        }

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: bar
                required property var modelData

                screen: modelData
                anchors { top: true; left: true; right: true }
                implicitHeight: Theme.pillH + 14
                color: "transparent"

                WifiMenu {
                    id: wifiMenu
                    barWindow: bar
                }

                AudioMenu {
                    id: audioMenu
                    barWindow: bar
                }

                // ================= слева =================
                RowLayout {
                    anchors { left: parent.left; leftMargin: 12; top: parent.top; topMargin: 9 }
                    spacing: 8

                    // логотип -> лаунчер
                    Pill {
                        implicitWidth: 48
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.pink }
                            GradientStop { position: 0.5; color: Theme.blue }
                            GradientStop { position: 1.0; color: Theme.mint }
                        }
                        Glyph {
                            anchors.centerIn: parent
                            text: ""
                            color: Theme.dark
                            font.pixelSize: 21
                        }
                        // лкм - приложения, пкм - меню питания
                        onClicked: mouse => mouse.button === Qt.RightButton ? powerMenu.toggle() : launcher.toggle()
                    }

                    // кисточка: лкм - темы, пкм - обои
                    Pill {
                        implicitWidth: Theme.pillH
                        color: hovered || stylePanel.open ? Theme.bgHover : Theme.bg
                        Glyph {
                            anchors.centerIn: parent
                            text: "\uf1fc"
                            color: Theme.pink
                            font.pixelSize: 15
                        }
                        onClicked: mouse => stylePanel.toggle(mouse.button === Qt.RightButton ? 1 : 0)
                    }

                    // воркспейсы
                    RowLayout {
                        spacing: 7
                        Repeater {
                            // теги mango: занятые и активные
                            model: (Mango.tags[bar.modelData.name] || []).filter(t => t.is_active || t.client_count > 0)

                            Pill {
                                id: ws
                                required property var modelData
                                readonly property bool active: modelData.is_active

                                implicitWidth: active ? Theme.pillH + 12 : Theme.pillH
                                color: active ? Theme.blue : (hovered ? Theme.bgHover : Theme.bg)

                                Glyph {
                                    anchors.centerIn: parent
                                    text: ws.modelData.index
                                    color: ws.active ? Theme.dark : Theme.fg
                                }
                                onClicked: mouse => Mango.view(ws.modelData.index, bar.modelData.name)
                            }
                        }
                    }

                    // трей (spotify, telegram и т.д.)
                    Pill {
                        visible: SystemTray.items.values.length > 0
                        implicitWidth: trayRow.implicitWidth + 24

                        RowLayout {
                            id: trayRow
                            anchors.centerIn: parent
                            spacing: 12

                            Repeater {
                                model: SystemTray.items

                                Item {
                                    id: trayItem
                                    required property var modelData
                                    implicitWidth: 21
                                    implicitHeight: 21

                                    IconImage {
                                        anchors.fill: parent
                                        source: trayItem.modelData.icon
                                        asynchronous: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            const item = trayItem.modelData;
                                            if (mouse.button === Qt.RightButton || item.onlyMenu) {
                                                if (item.hasMenu) {
                                                    const p = trayItem.mapToItem(null, 0, trayItem.height);
                                                    item.display(bar, p.x, p.y + 12);
                                                }
                                            } else {
                                                item.activate();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ================= центр: что играет =================
                Pill {
                    id: media
                    readonly property var player: {
                        const ps = Mpris.players.values;
                        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
                    }

                    visible: player !== null
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 9 }
                    implicitWidth: mediaRow.implicitWidth + 32

                    RowLayout {
                        id: mediaRow
                        anchors.centerIn: parent
                        spacing: 10

                        Glyph {
                            text: media.player?.isPlaying ? "" : ""
                            color: Theme.blue
                            font.pixelSize: 12
                        }
                        Glyph {
                            Layout.maximumWidth: 460
                            elide: Text.ElideRight
                            text: {
                                const p = media.player;
                                if (!p) return "";
                                const artist = p.trackArtist || "";
                                const title = p.trackTitle || "unknown";
                                return (artist ? artist + " - " + title : title).toLowerCase();
                            }
                        }
                    }

                    // лкм: пауза, пкм: следующий, скм: предыдущий
                    onClicked: mouse => {
                        const p = media.player;
                        if (!p) return;
                        if (mouse.button === Qt.RightButton) { if (p.canGoNext) p.next(); }
                        else if (mouse.button === Qt.MiddleButton) { if (p.canGoPrevious) p.previous(); }
                        else if (p.canTogglePlaying) p.togglePlaying();
                    }
                }

                // ================= справа =================
                RowLayout {
                    anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 9 }
                    spacing: 8

                    // громкость: лкм - меню звука, пкм - mute, колесо - громкость
                    Pill {
                        id: vol
                        readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
                        readonly property bool micMuted: Pipewire.defaultAudioSource?.audio?.muted ?? false
                        visible: audio !== null
                        implicitWidth: volRow.implicitWidth + 28
                        color: hovered || audioMenu.open ? Theme.bgHover : Theme.bg

                        RowLayout {
                            id: volRow
                            anchors.centerIn: parent
                            spacing: 8
                            Glyph {
                                text: !vol.audio || vol.audio.muted ? ""
                                    : vol.audio.volume > 0.5 ? "" : ""
                                font.pixelSize: Theme.iconSize
                            }
                            Glyph {
                                text: vol.audio && vol.audio.muted ? "mute"
                                    : Math.round((vol.audio?.volume ?? 0) * 100) + "%"
                            }
                            Glyph {
                                visible: vol.micMuted
                                text: "\uf131"
                                color: Theme.pink
                                font.pixelSize: Theme.iconSize
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (vol.audio) vol.audio.muted = !vol.audio.muted;
                                return;
                            }
                            // меню по центру кнопки, но не вылезая за экран
                            const c = vol.mapToItem(null, vol.width / 2, 0).x;
                            const w = audioMenu.menuWidth;
                            audioMenu.leftOffset = Math.max(12, Math.min(bar.width - w - 12, Math.round(c - w / 2)));
                            audioMenu.open = !audioMenu.open;
                        }
                        onScrolled: event => {
                            if (!vol.audio) return;
                            const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
                            vol.audio.volume = Math.max(0, Math.min(1, vol.audio.volume + step));
                        }
                    }

                    // сеть: wifi, а если адаптера нет (пк) или подключён кабель - статус кабеля
                    // клик - меню wifi (если есть адаптер)
                    Pill {
                        id: wifiPill
                        readonly property bool wired: !Net.hasWifi || (Net.wiredUp && !Net.ssid)
                        readonly property bool online: wired ? Net.wiredUp : Net.ssid !== ""
                        readonly property string label: {
                            if (wired) {
                                return Net.wiredUp ? "ethernet" : "no cable";
                            }
                            return !Net.powered ? "wifi off" : (Net.ssid || "offline");
                        }

                        implicitWidth: wifiRow.implicitWidth + 28
                        color: hovered || wifiMenu.open ? Theme.bgHover : Theme.bg

                        RowLayout {
                            id: wifiRow
                            anchors.centerIn: parent
                            spacing: 9
                            Glyph {
                                // nf-md-ethernet / nf-fa-wifi
                                text: wifiPill.wired ? "\udb80\ude00" : ""
                                font.pixelSize: Theme.iconSize
                                color: wifiPill.online ? Theme.fg : Theme.fgDim
                            }
                            Glyph {
                                text: wifiPill.label
                                color: wifiPill.online ? Theme.fg : Theme.fgDim
                            }
                        }
                        onClicked: mouse => {
                            if (!Net.hasWifi) return;
                            // меню по центру кнопки, но не вылезая за экран
                            const c = wifiPill.mapToItem(null, wifiPill.width / 2, 0).x;
                            const w = 390;
                            wifiMenu.leftOffset = Math.max(12, Math.min(bar.width - w - 12, Math.round(c - w / 2)));
                            wifiMenu.open = !wifiMenu.open;
                        }
                    }

                    // квадратики = загрузка cpu
                    Pill {
                        implicitWidth: dotsRow.implicitWidth + 28

                        RowLayout {
                            id: dotsRow
                            anchors.centerIn: parent
                            spacing: 6
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    implicitWidth: 8
                                    implicitHeight: 8
                                    radius: 2
                                    color: index < Math.max(1, Math.ceil(root.cpu * 4)) ? Theme.fg : Theme.fgDim
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                            }
                        }
                        onClicked: mouse => Quickshell.execDetached([ "trun", "btop" ])
                    }

                    // батарея
                    Pill {
                        id: bat
                        readonly property var dev: UPower.displayDevice
                        readonly property int pct: Math.round((dev?.percentage ?? 0) * 100)
                        readonly property bool charging: dev?.state === UPowerDeviceState.Charging

                        visible: dev?.isLaptopBattery ?? false
                        implicitWidth: batRow.implicitWidth + 28

                        RowLayout {
                            id: batRow
                            anchors.centerIn: parent
                            spacing: 8
                            Glyph {
                                font.pixelSize: Theme.iconSize
                                color: bat.pct <= 15 && !bat.charging ? Theme.pink : Theme.fg
                                text: bat.charging ? ""
                                    : bat.pct > 85 ? ""
                                    : bat.pct > 60 ? ""
                                    : bat.pct > 35 ? ""
                                    : bat.pct > 10 ? "" : ""
                            }
                            Glyph { text: bat.pct + "%" }
                        }
                    }

                    // часы: клик - показать дату
                    Pill {
                        id: clockPill
                        property bool showDate: false
                        implicitWidth: clockText.implicitWidth + 32
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.white }
                            GradientStop { position: 0.6; color: Theme.white }
                            GradientStop { position: 1.0; color: Theme.pink }
                        }

                        Glyph {
                            id: clockText
                            anchors.centerIn: parent
                            color: Theme.dark
                            text: Qt.formatDateTime(clock.date,
                                clockPill.showDate ? "ddd dd.MM  HH:mm" : "HH:mm")
                        }
                        onClicked: mouse => clockPill.showDate = !clockPill.showDate
                    }
                }
            }
        }
    }
  '';
}
