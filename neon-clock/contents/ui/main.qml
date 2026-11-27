import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---------- configuration ----------
    readonly property bool use24Hour: Plasmoid.configuration.use24Hour
    readonly property bool showSeconds: Plasmoid.configuration.showSeconds
    readonly property bool showDate: Plasmoid.configuration.showDate
    readonly property bool glowEnabled: Plasmoid.configuration.glow
    readonly property real glowStrength: Plasmoid.configuration.glowStrength / 100   // 0..1, default 0.7
    readonly property bool glitchEnabled: Plasmoid.configuration.glitchEffect
    readonly property bool scanlinesEnabled: Plasmoid.configuration.scanlines
    readonly property bool sweepEnabled: Plasmoid.configuration.scanSweep
    readonly property color primary: Plasmoid.configuration.primaryColor
    readonly property color accent: Plasmoid.configuration.accentColor
    readonly property color highlight: "#fcee0a"
    readonly property real backgroundAlpha: Plasmoid.configuration.backgroundOpacity / 100
    // Holo style: corner brackets + soft fading backdrop instead of a solid box
    readonly property bool holo: Plasmoid.configuration.style === 1
    readonly property bool borderEnabled: Plasmoid.configuration.showBorder
    readonly property bool headerEnabled: Plasmoid.configuration.showHeader
    readonly property string fontFamily: Plasmoid.configuration.fontFamily || "monospace"

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                 || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The full view is on screen: always on the desktop, only while the popup is open in a panel
    readonly property bool fullShown: !inPanel || expanded

    // ---------- clock state ----------
    property var now: new Date()

    readonly property bool blink: now.getMilliseconds() < 500
    readonly property int seconds: now.getSeconds()
    readonly property int displayHours: use24Hour ? now.getHours() : (now.getHours() % 12 || 12)
    readonly property string shortTimeText: pad(displayHours, 2) + ":" + pad(now.getMinutes(), 2)
    readonly property string timeText: shortTimeText + (showSeconds ? ":" + pad(seconds, 2) : "")
    readonly property string meridiem: now.getHours() < 12 ? "AM" : "PM"
    readonly property string dateText: Qt.formatDate(now, "ddd").toUpperCase()
                                       + " // " + Qt.formatDate(now, "dd.MMM.yyyy").toUpperCase()
    readonly property string calendarText: "WK" + pad(isoWeek(now), 2) + " · D" + pad(dayOfYear(now), 3)
    readonly property string hexStamp: "0x" + Math.floor(now.getTime() / 1000).toString(16).toUpperCase()

    // ---------- glitch state ----------
    property bool glitching: false
    property int glitchFrames: 0
    property real glitchX: 0      // horizontal jitter, in units of `u`
    property real sliceY: 0       // fraction of time box height
    property real sliceH: 0
    property real sliceX: 0       // in units of `u`

    function pad(n, width) {
        let s = String(n);
        while (s.length < width) s = "0" + s;
        return s;
    }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1);
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
    }
    function dayOfYear(d) {
        return Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())
                           - Date.UTC(d.getFullYear(), 0, 0)) / 86400000);
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: Qt.formatTime(now, Qt.locale().timeFormat(Locale.LongFormat))
    toolTipSubText: Qt.formatDate(now, Qt.locale().dateFormat(Locale.LongFormat))

    // Ticks on every half-second boundary so seconds and the blink stay in sync.
    // In a panel with the popup closed only HH:MM is shown, so it ticks once a
    // minute (on the minute) instead.
    Timer {
        id: tick
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            interval = root.fullShown
                ? 500 - (root.now.getMilliseconds() % 500) + 5
                : 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()) + 5;
        }
    }
    // switching between the two rates: update right away, then continue at the new rate
    onFullShownChanged: tick.restart()

    Timer {
        id: glitchScheduler
        interval: 4000
        repeat: true
        running: root.glitchEnabled && root.fullShown      // nobody sees glitches otherwise
        onTriggered: {
            interval = 2500 + Math.random() * 7000;
            root.glitchFrames = 3 + Math.floor(Math.random() * 4);
            glitchBurst.start();
        }
    }
    Timer {
        id: glitchBurst
        interval: 55
        repeat: true
        onTriggered: {
            if (root.glitchFrames-- <= 0) {
                stop();
                root.glitching = false;
                root.glitchX = 0;
                return;
            }
            root.glitching = true;
            root.glitchX = (Math.random() - 0.5) * 0.6;
            root.sliceY = Math.random() * 0.75;
            root.sliceH = 0.08 + Math.random() * 0.22;
            root.sliceX = (Math.random() - 0.5) * 1.6;
        }
    }

    // Note: inline components can't see ids from this file (like `root`),
    // so anything that depends on root is set where they're used.
    component TimeLabel: Text {
        font.bold: true
        font.features: { "tnum": 1 }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component HudLabel: Text {
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
    }

    // ================= panel view =================
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.minimumWidth: vertical ? 0 : compactLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? compactLabel.implicitHeight : 0
        onClicked: root.expanded = !root.expanded

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -Math.max(1, compactLabel.font.pixelSize * 0.06)
            text: compactLabel.text
            font: compactLabel.font
            color: root.accent
            opacity: 0.8
        }
        Text {
            id: compactLabel
            anchors.centerIn: parent
            text: root.shortTimeText
            color: root.primary
            font.family: root.fontFamily
            font.bold: true
            font.features: { "tnum": 1 }
            font.pixelSize: compact.vertical ? compact.width * 0.28 : compact.height * 0.55
        }
    }

    // ================= desktop / popup view =================
    fullRepresentation: Item {
        id: full

        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 11
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8

        // Scale unit: everything is sized relative to this so the widget resizes cleanly.
        readonly property real u: Math.max(4, Math.min(width / 24, height / 11))
        // Text never shrinks below this, so HUD labels stay readable at small sizes.
        readonly property real minText: Kirigami.Units.gridUnit * 0.7
        function textSize(k) { return Math.max(minText, u * k); }

        // Holo: dark backdrop that fades to transparent at the edges, so the
        // wallpaper shows through around the widget while the text stays readable.
        Item {
            id: fadeSource
            anchors.fill: frame
            visible: false
            Rectangle {
                anchors.fill: parent
                anchors.margins: full.u * 1.2
                radius: full.u
                color: Qt.rgba(0.02, 0.02, 0.07, root.backgroundAlpha)
            }
        }
        MultiEffect {
            anchors.fill: fadeSource
            source: fadeSource
            visible: root.holo && root.backgroundAlpha > 0
            autoPaddingEnabled: true
            blurEnabled: true
            blurMax: 64
            blur: 1.0
        }

        // Chamfered HUD frame (outline in Panel style, corner brackets in Holo style)
        Item {
            id: frame
            anchors.fill: parent
            anchors.margins: Math.round(full.u * 0.4)
            readonly property real c: full.u * 1.6
        }

        Shape {
            id: frameShape
            anchors.fill: frame
            visible: !root.holo
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                // no outline when the border is off; the background shape stays
                strokeColor: root.borderEnabled ? root.withAlpha(root.primary, 0.6) : "transparent"
                strokeWidth: Math.max(1, full.u * 0.08)
                fillColor: Qt.rgba(0.02, 0.02, 0.07, root.backgroundAlpha)
                joinStyle: ShapePath.MiterJoin
                startX: frame.c; startY: 0
                PathLine { x: frame.width;           y: 0 }
                PathLine { x: frame.width;           y: frame.height - frame.c }
                PathLine { x: frame.width - frame.c; y: frame.height }
                PathLine { x: 0;                     y: frame.height }
                PathLine { x: 0;                     y: frame.c }
                PathLine { x: frame.c;               y: 0 }
            }
        }

        // Holo corner brackets: same chamfered silhouette, only the corners drawn
        Shape {
            anchors.fill: frame
            id: brackets
            visible: root.holo && root.borderEnabled
            layer.enabled: true
            layer.samples: 4
            readonly property real w: frame.width
            readonly property real h: frame.height
            readonly property real c: frame.c
            readonly property real arm: full.u * 1.8   // length of each bracket arm

            ShapePath {
                strokeColor: root.withAlpha(root.primary, 0.8)
                strokeWidth: Math.max(1, full.u * 0.12)
                fillColor: "transparent"
                joinStyle: ShapePath.MiterJoin
                capStyle: ShapePath.FlatCap

                // top-left (chamfered)
                startX: 0; startY: brackets.c + brackets.arm
                PathLine { x: 0;                         y: brackets.c }
                PathLine { x: brackets.c;                  y: 0 }
                PathLine { x: brackets.c + brackets.arm;     y: 0 }
                // top-right
                PathMove { x: brackets.w - brackets.arm;     y: 0 }
                PathLine { x: brackets.w;                  y: 0 }
                PathLine { x: brackets.w;                  y: brackets.arm }
                // bottom-right (chamfered)
                PathMove { x: brackets.w;                  y: brackets.h - brackets.c - brackets.arm }
                PathLine { x: brackets.w;                  y: brackets.h - brackets.c }
                PathLine { x: brackets.w - brackets.c;       y: brackets.h }
                PathLine { x: brackets.w - brackets.c - brackets.arm; y: brackets.h }
                // bottom-left
                PathMove { x: brackets.arm;                y: brackets.h }
                PathLine { x: 0;                         y: brackets.h }
                PathLine { x: 0;                         y: brackets.h - brackets.arm }
            }
        }

        Rectangle {
            visible: root.borderEnabled
            x: frame.x + frame.width - width - full.u * 2
            y: frame.y - height / 2
            width: full.u * 5
            height: full.u * 0.3
            color: root.accent
        }
        Rectangle {
            visible: root.borderEnabled
            x: frame.x + full.u * 2
            y: frame.y + frame.height - height / 2
            width: full.u * 3
            height: full.u * 0.3
            color: root.primary
        }

        // Slow sweeping scan band. Moved by a ~15 fps timer instead of an animation:
        // it's slow enough to look the same, and costs a quarter of the redraws.
        Timer {
            interval: 66
            repeat: true
            running: sweepArea.visible
            onTriggered: {
                const travel = sweepArea.height + sweepBand.height;
                sweepBand.y += travel / (5000 / interval);
                if (sweepBand.y > sweepArea.height)
                    sweepBand.y = -sweepBand.height;
            }
        }
        Item {
            id: sweepArea
            anchors.fill: frame
            anchors.margins: frame.c * 0.5
            clip: true
            visible: root.sweepEnabled

            Rectangle {
                id: sweepBand
                width: parent.width
                height: parent.height * 0.3
                y: -height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: root.withAlpha(root.primary, 0.08) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: frame
            anchors.leftMargin: full.u * 1.4
            anchors.rightMargin: full.u * 1.4
            anchors.topMargin: full.u * 0.9
            anchors.bottomMargin: full.u * 0.9
            spacing: full.u * 0.35
            opacity: root.glitching ? 0.85 : 1

            // ---- header ----
            RowLayout {
                visible: root.headerEnabled
                Layout.fillWidth: true
                spacing: full.u * 0.5

                Rectangle {
                    Layout.preferredWidth: full.u * 0.45
                    Layout.preferredHeight: full.u * 0.45
                    color: root.accent
                    opacity: root.blink ? 1 : 0.2
                }
                HudLabel {
                    font.family: root.fontFamily
                    text: "SYS.CHRONO"
                    color: root.primary
                    font.pixelSize: full.textSize(0.85)
                    font.letterSpacing: full.u * 0.08
                    opacity: 0.8
                    Layout.fillWidth: true
                }
                HudLabel {
                    font.family: root.fontFamily
                    text: root.hexStamp
                    font.pixelSize: full.textSize(0.85)
                    color: root.accent
                }
            }

            // ---- divider ----
            Item {
                visible: root.headerEnabled
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(2, full.u * 0.12)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: root.withAlpha(root.primary, 0.4)
                }
                Rectangle {
                    width: full.u * 3
                    height: parent.height
                    color: root.accent
                }
            }

            // ---- time ----
            Item {
                id: timeArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    spacing: full.u * 0.4

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Holo: soft dark shadow under the digits for contrast on bright
                        // wallpapers. brightness -1 turns the blurred copy pure black, so
                        // only the shadow is drawn (declared first so it sits underneath).
                        MultiEffect {
                            anchors.fill: timeBox
                            source: timeBox
                            visible: root.holo
                            autoPaddingEnabled: true
                            blurEnabled: true
                            blurMax: 48
                            blur: 1.0
                            brightness: -1.0
                            opacity: 0.6
                        }

                        Item {
                            id: timeBox
                            anchors.fill: parent
                            z: 1
                            readonly property real aberration: full.u * 0.12

                            // Measure the digits' actual ink at 100px, then scale so they fill the box.
                            // A fixed sample string keeps the size steady as digits change.
                            TextMetrics {
                                id: timeMetrics
                                font.family: root.fontFamily
                                font.bold: true
                                font.features: { "tnum": 1 }
                                font.pixelSize: 100
                                text: root.showSeconds ? "00:00:00" : "00:00"
                            }
                            FontMetrics {
                                id: timeFontMetrics
                                font: timeMetrics.font
                            }
                            readonly property real fittedSize: Math.max(6, Math.floor(100 * Math.min(
                                width * 0.97 / Math.max(1, timeMetrics.advanceWidth),
                                height * 0.92 / Math.max(1, timeMetrics.tightBoundingRect.height))))
                            // Text centres the full line box; shift so the digits' ink is centred instead.
                            readonly property real inkOffset: fittedSize / 100 * (
                                (timeFontMetrics.descent - timeFontMetrics.ascent) / 2
                                - (timeMetrics.tightBoundingRect.y + timeMetrics.tightBoundingRect.height / 2))

                            TimeLabel {
                                anchors.fill: parent
                                text: root.timeText
                                font.family: root.fontFamily
                                font.pixelSize: timeBox.fittedSize
                                color: root.accent
                                opacity: 0.75
                                transform: Translate {
                                    x: -timeBox.aberration - root.glitchX * full.u
                                    y: timeBox.inkOffset
                                }
                            }
                            TimeLabel {
                                anchors.fill: parent
                                text: root.timeText
                                font.family: root.fontFamily
                                font.pixelSize: timeBox.fittedSize
                                color: root.highlight
                                opacity: 0.6
                                visible: root.glitching
                                transform: Translate {
                                    x: timeBox.aberration + root.glitchX * full.u * 1.5
                                    y: timeBox.inkOffset
                                }
                            }
                            TimeLabel {
                                anchors.fill: parent
                                text: root.timeText
                                font.family: root.fontFamily
                                font.pixelSize: timeBox.fittedSize
                                // Neon tubes have a hot, near-white core when glowing
                                color: root.glowEnabled ? Qt.lighter(root.primary, 1 + 0.57 * root.glowStrength) : root.primary
                                transform: Translate {
                                    x: root.glitchX * full.u * 0.5
                                    y: timeBox.inkOffset
                                }
                            }
                            // Displaced horizontal slice during glitch bursts
                            Item {
                                visible: root.glitching
                                y: root.sliceY * timeBox.height
                                width: timeBox.width
                                height: root.sliceH * timeBox.height
                                clip: true
                                TimeLabel {
                                    x: root.sliceX * full.u
                                    y: -parent.y + timeBox.inkOffset
                                    width: timeBox.width
                                    height: timeBox.height
                                    text: root.timeText
                                    font.family: root.fontFamily
                                    font.pixelSize: timeBox.fittedSize
                                    color: Qt.lighter(root.primary, 1.35)
                                }
                            }
                        }

                        // Wide outer halo (drawn first, underneath)
                        MultiEffect {
                            anchors.fill: timeBox
                            source: timeBox
                            visible: root.glowEnabled
                            autoPaddingEnabled: true
                            blurEnabled: true
                            blurMax: 64
                            blur: 1.0
                            colorization: 1.0
                            colorizationColor: root.primary
                            brightness: 0.5 * root.glowStrength
                            opacity: Math.min(1, root.glowStrength * 1.4)
                        }
                        // Tight inner glow (timeBox draws the sharp digits on top)
                        MultiEffect {
                            anchors.fill: timeBox
                            source: timeBox
                            visible: root.glowEnabled
                            autoPaddingEnabled: true
                            blurEnabled: true
                            blurMax: 32
                            blur: 0.8
                            colorization: 1.0
                            colorizationColor: root.primary
                            opacity: Math.min(1, 0.3 + root.glowStrength)
                            scale: 1 + 0.03 * root.glowStrength
                        }
                    }

                    HudLabel {
                        font.family: root.fontFamily
                        visible: !root.use24Hour
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: full.u * 0.6
                        text: root.meridiem
                        color: root.accent
                        font.bold: true
                        font.pixelSize: full.textSize(1.4)
                    }
                }

                // Static CRT scanlines over the digits
                Canvas {
                    anchors.fill: parent
                    visible: root.scanlinesEnabled
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = "rgba(0, 0, 0, 0.35)";
                        for (let y = 0; y < height; y += 3)
                            ctx.fillRect(0, y, width, 1);
                    }
                }
            }

            // ---- footer ----
            RowLayout {
                id: footer
                Layout.fillWidth: true
                visible: root.showDate
                spacing: full.u * 0.8

                HudLabel {
                    font.family: root.fontFamily
                    id: dateLabel
                    text: root.dateText
                    color: root.primary
                    font.pixelSize: full.textSize(1.0)
                    font.bold: true
                    Layout.fillWidth: true
                    // Shrink slightly to fit instead of truncating
                    elide: Text.ElideNone
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: full.minText * 0.8
                }
                HudLabel {
                    font.family: root.fontFamily
                    // Hide the week/day readout when there isn't room for both
                    visible: footer.width >= dateLabel.implicitWidth + implicitWidth + footer.spacing
                    text: root.calendarText
                    font.pixelSize: full.textSize(0.9)
                    color: root.accent
                    opacity: 0.9
                }
            }
        }
    }
}
