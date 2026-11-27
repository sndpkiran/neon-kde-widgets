import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
// Plasma's own MPRIS module (used by its Media Player widget). It's a private
// module, so its API can change between Plasma versions.
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root

    // ---------- configuration ----------
    readonly property int artStyle: Plasmoid.configuration.artStyle     // 0 tint, 1 original, 2 hidden
    readonly property bool showAlbum: Plasmoid.configuration.showAlbum
    readonly property bool glitchOnChange: Plasmoid.configuration.glitchOnChange
    readonly property bool showVolume: Plasmoid.configuration.showVolume
    readonly property bool showShuffleRepeat: Plasmoid.configuration.showShuffleRepeat
    readonly property bool showRemaining: Plasmoid.configuration.showRemaining

    readonly property bool holo: Plasmoid.configuration.style === 1
    readonly property int progressBarStyle: Plasmoid.configuration.progressBarStyle
    readonly property int volumeBarStyle: Plasmoid.configuration.volumeBarStyle
    readonly property bool borderEnabled: Plasmoid.configuration.showBorder
    readonly property bool headerEnabled: Plasmoid.configuration.showHeader
    readonly property bool glowEnabled: Plasmoid.configuration.glow
    readonly property bool scanlinesEnabled: Plasmoid.configuration.scanlines
    readonly property bool sweepEnabled: Plasmoid.configuration.scanSweep
    readonly property color primary: Plasmoid.configuration.primaryColor
    // Accent: the chosen color, or (optional) a neon color taken from the album art
    readonly property color baseAccent: Plasmoid.configuration.accentColor
    readonly property bool artAccentOn: Plasmoid.configuration.artAccent
    readonly property bool artBackdropOn: Plasmoid.configuration.artBackdrop
    readonly property color accent: artAccentOn && artAccent.valid ? artAccent.color : baseAccent
    readonly property real backgroundAlpha: Plasmoid.configuration.backgroundOpacity / 100
    readonly property string fontFamily: Plasmoid.configuration.fontFamily || "monospace"

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                 || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The full view is on screen: always on the desktop, only while the popup is open in a panel
    readonly property bool fullShown: !inPanel || expanded

    // ---------- player ----------
    // Mpris2Model lists an "automatic" entry (follows the active player) plus each
    // open player. Which one is shown is decided below (ignore / prefer / switcher).
    Mpris.Mpris2Model { id: mpris }
    readonly property var player: noPlayerSelected ? null : mpris.currentPlayer
    readonly property bool hasPlayer: !!player
    readonly property bool playing: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property bool paused: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Paused
    readonly property string track: hasPlayer ? (player.track || "") : ""
    readonly property string artist: hasPlayer ? (player.artist || "") : ""
    readonly property string album: hasPlayer ? (player.album || "") : ""
    readonly property string artUrl: hasPlayer ? (player.artUrl || "") : ""
    readonly property string identity: hasPlayer ? (player.identity || "") : ""
    // MPRIS times are in microseconds
    readonly property real lengthUs: hasPlayer ? Math.max(0, player.length) : 0
    readonly property real positionUs: hasPlayer ? Math.max(0, player.position) : 0
    readonly property bool canSeek: hasPlayer && player.canSeek && lengthUs > 0

    // Shuffle / repeat / volume: only offered when the player reports them
    readonly property bool canShuffle: hasPlayer && player.canControl && player.shuffle !== Mpris.ShuffleStatus.Unknown
    readonly property bool shuffleOn: hasPlayer && player.shuffle === Mpris.ShuffleStatus.On
    readonly property bool canLoop: hasPlayer && player.canControl && player.loopStatus !== Mpris.LoopStatus.Unknown
    readonly property int loopStatus: hasPlayer ? player.loopStatus : Mpris.LoopStatus.Unknown
    readonly property real volume: hasPlayer ? player.volume : -1          // 0..1, -1 = not reported
    readonly property bool hasVolume: hasPlayer && player.canControl && volume >= 0

    // ---------- accent from album art ----------
    // A hidden copy of the cover feeds Kirigami's color extraction (the same tool
    // Plasma's media widget uses). The most vivid color that covers a fair part of
    // the cover is pushed to neon brightness; grey covers keep the chosen accent.
    Image {
        id: colorSource
        visible: false
        width: 64
        height: 64
        sourceSize.width: 64
        sourceSize.height: 64
        source: root.artAccentOn ? root.artUrl : ""
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) artColors.update()
    }
    Kirigami.ImageColors {
        id: artColors
        source: colorSource
    }
    QtObject {
        id: artAccent
        readonly property color color: pick ? pick : "transparent"
        readonly property bool valid: !!pick && root.artUrl !== "" && colorSource.status === Image.Ready
        readonly property var pick: {
            let best = null, bestScore = 0;
            for (const e of artColors.palette) {
                const c = e.color;
                if (c.hslLightness < 0.12 || c.hslLightness > 0.92)
                    continue;                                  // near black / white
                const score = c.hslSaturation * Math.sqrt(e.ratio);
                if (score > bestScore) { best = c; bestScore = score; }
            }
            if (!best || best.hslSaturation < 0.25)
                return null;                                   // greyscale cover
            return Qt.hsla(best.hslHue, Math.max(0.75, best.hslSaturation),
                           Math.min(0.65, Math.max(0.55, best.hslLightness)), 1);
        }
    }

    // ---------- which player to show ----------
    // Settings can ignore players (all web browsers, or by name) and prefer one.
    // Order: the preferred player if it's playing, else any player that's playing,
    // else the preferred player (paused), else the most recently active one.
    // Clicking the player name in the header cycles AUTO -> each player -> AUTO.
    readonly property bool ignoreBrowsers: Plasmoid.configuration.ignoreBrowsers
    readonly property var ignoredNames: String(Plasmoid.configuration.ignoredPlayers || "")
                                            .split(",").map(n => n.trim().toLowerCase()).filter(n => n.length > 0)
    readonly property string preferredName: String(Plasmoid.configuration.preferredPlayer || "").trim().toLowerCase()
    // With no rules and no manual pick, just use the model's own automatic entry
    readonly property bool customSelection: ignoreBrowsers || ignoredNames.length > 0
                                            || preferredName !== "" || lockedName !== ""

    property string lockedName: ""          // identity picked with the switcher ("" = auto)
    property bool noPlayerSelected: false   // every open player is ignored
    property int candidateCount: 0          // players that aren't ignored

    Instantiator {
        id: playerList
        model: mpris
        delegate: QtObject {
            required property bool isMultiplexer
            required property string identity
            required property var desktopEntry
            required property int playbackStatus
            onPlaybackStatusChanged: root.updateSelection()
        }
        onObjectAdded: root.updateSelection()
        onObjectRemoved: root.updateSelection()
    }
    onCustomSelectionChanged: updateSelection()
    onIgnoredNamesChanged: updateSelection()
    onPreferredNameChanged: updateSelection()
    onIgnoreBrowsersChanged: updateSelection()
    // players can change state without the model telling us everything; re-check now and
    // then (only needed when ignore/prefer rules or a manual pick are in effect)
    Timer {
        interval: 2000
        repeat: true
        running: root.customSelection
        onTriggered: root.updateSelection()
    }

    function nameMatches(entry, name) {
        const id = String(entry.identity || "").toLowerCase();
        const de = String(entry.desktopEntry || "").toLowerCase();
        return id === name || de === name || (name.length >= 3 && (id.includes(name) || de.includes(name)));
    }
    function isBrowser(entry) {
        const t = (String(entry.identity || "") + " " + String(entry.desktopEntry || "")).toLowerCase();
        return /firefox|chrom|brave|vivaldi|opera|msedge|microsoft edge|epiphany|falkon|librewolf|floorp|waterfox|\bzen\b|plasma-browser-integration/.test(t);
    }
    function isIgnored(entry) {
        return (ignoreBrowsers && isBrowser(entry)) || ignoredNames.some(n => nameMatches(entry, n));
    }
    // Open players that aren't ignored, each with its row in the model
    function candidates() {
        const out = [];
        for (let i = 0; i < playerList.count; i++) {
            const e = playerList.objectAt(i);
            if (e && !e.isMultiplexer && !isIgnored(e))
                out.push({ row: i, identity: e.identity, entry: e,
                           playing: e.playbackStatus === Mpris.PlaybackStatus.Playing });
        }
        return out;
    }
    function chooseCandidate(cands) {
        if (lockedName !== "") {
            const locked = cands.find(c => c.identity === lockedName);
            if (locked)
                return locked;
        }
        const preferred = preferredName ? cands.find(c => nameMatches(c.entry, preferredName)) : null;
        if (preferred && preferred.playing)
            return preferred;
        const playing = cands.find(c => c.playing);
        if (playing)
            return playing;
        if (preferred)
            return preferred;
        // most recently active: what the model's automatic entry is showing, if allowed
        for (let i = 0; i < playerList.count; i++) {
            const e = playerList.objectAt(i);
            if (e && e.isMultiplexer) {
                const recent = cands.find(c => c.identity === e.identity);
                if (recent)
                    return recent;
            }
        }
        return cands.length ? cands[0] : null;
    }
    function updateSelection() {
        const cands = candidates();
        candidateCount = cands.length;
        if (lockedName !== "" && !cands.some(c => c.identity === lockedName))
            lockedName = "";                                   // locked player closed
        let row = -1;
        if (!customSelection) {
            for (let i = 0; i < playerList.count; i++) {
                const e = playerList.objectAt(i);
                if (e && e.isMultiplexer) { row = i; break; }
            }
            noPlayerSelected = false;
        } else {
            const chosen = chooseCandidate(cands);
            noPlayerSelected = !chosen;
            row = chosen ? chosen.row : -1;
        }
        if (row >= 0 && mpris.currentIndex !== row)
            mpris.currentIndex = row;
    }

    readonly property bool canSwitch: candidateCount > 1
    readonly property bool autoPlayer: lockedName === ""
    function nextPlayer() {
        const names = [""].concat(candidates().map(c => c.identity));
        lockedName = names[(names.indexOf(lockedName) + 1) % names.length];
        updateSelection();
    }

    // The player only reports its position on changes, so ask for it while playing
    // (and only while the progress bar is on screen)
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.fullShown
        triggeredOnStart: true
        onTriggered: if (root.player) root.player.updatePosition()
    }

    function togglePlay() { if (player && player.canControl) player.PlayPause(); }
    function next() { if (player && player.canGoNext) player.Next(); }
    function previous() { if (player && player.canGoPrevious) player.Previous(); }
    function seekTo(fraction) {
        if (!canSeek)
            return;
        player.position = Math.max(0, Math.min(1, fraction)) * lengthUs;
        positionRefresh.restart();       // read back the new position right away
    }
    Timer {
        id: positionRefresh
        interval: 250
        onTriggered: if (root.player) root.player.updatePosition()
    }
    function toggleRemaining() {
        Plasmoid.configuration.showRemaining = !showRemaining;
    }
    function toggleShuffle() {
        if (canShuffle)
            player.shuffle = shuffleOn ? Mpris.ShuffleStatus.Off : Mpris.ShuffleStatus.On;
    }
    // off -> playlist -> track -> off
    function cycleLoop() {
        if (!canLoop)
            return;
        player.loopStatus = loopStatus === Mpris.LoopStatus.None ? Mpris.LoopStatus.Playlist
                          : loopStatus === Mpris.LoopStatus.Playlist ? Mpris.LoopStatus.Track
                          : Mpris.LoopStatus.None;
    }
    function setVolume(fraction) {
        if (hasVolume)
            player.volume = Math.max(0, Math.min(1, fraction));
    }
    function raisePlayer() {
        if (player && player.canRaise)
            player.Raise();
    }
    function changeVolume(up) {
        if (player && player.canControl)
            player.changeVolume(up ? 0.05 : -0.05, true);
    }

    function clock(us) {
        if (!(us > 0))
            return "0:00";
        const t = Math.floor(us / 1e6), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = t % 60;
        const ss = (sec < 10 ? "0" : "") + sec;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + a + ")";
    }

    // Shared blink phase (header light, paused state); only needed while the full view is shown
    property bool blink: false
    Timer {
        interval: 500
        repeat: true
        running: root.fullShown
        onTriggered: root.blink = !root.blink
    }

    // ---------- glitch burst on track change ----------
    property bool glitching: false
    property int glitchFrames: 0
    property real glitchX: 0          // horizontal jitter, in units of u
    onTrackChanged: {
        if (glitchOnChange && track !== "") {
            glitchFrames = 7;
            glitchBurst.restart();
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
            root.glitchX = (Math.random() - 0.5) * 0.8;
        }
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: hasPlayer && track ? track : i18n("No media playing")
    toolTipSubText: hasPlayer ? [artist, identity].filter(s => s).join("  ·  ") : ""

    // Note: inline components can't see ids from this file (like `root`),
    // so anything that depends on root is set where they're used.

    // One line of text that scrolls back and forth when it's too long to fit:
    // pause at the start, scroll to the end, pause, slide back. It does this a
    // couple of times after each new track, then rests at the start; while the
    // pointer is over the widget it keeps going. (Scrolling redraws at full frame
    // rate, so doing it non-stop would cost a few % CPU.)
    // Optional chromatic-split glitch copy (used by the title on track change).
    component ScrollText: Item {
        id: st
        property string text
        property string fontFamily: "monospace"
        property bool bold: false
        property real pixelSize: 12
        property real letterSpacing: 0
        property color color: "cyan"
        property real u: 8                    // scroll speed is ~2.5 units per second
        property var resetKey                 // scroll restarts from the start when this changes
        property bool hovered: false          // keep scrolling while the pointer is over the widget
        property int repeats: 2               // passes after each new track
        property int passesLeft: 0
        property bool glitching: false
        property real glitchX: 0              // in units of u
        property color glitchColor: "magenta"

        implicitHeight: label.implicitHeight
        clip: true

        readonly property real overflow: Math.max(0, label.implicitWidth - width)
        readonly property bool scrolls: overflow > 1 && visible

        // Both texts move together, so the glitch copy follows the scroll
        Item {
            id: marquee
            width: label.implicitWidth
            height: parent.height

            Text {
                visible: st.glitching
                text: st.text
                font: label.font
                color: st.glitchColor
                opacity: 0.8
                transform: Translate { x: -st.u * 0.15 - st.glitchX * st.u }
            }
            Text {
                id: label
                text: st.text
                font.family: st.fontFamily
                font.bold: st.bold
                font.pixelSize: st.pixelSize
                font.letterSpacing: st.letterSpacing
                color: st.color
                transform: Translate { x: st.glitchX * st.u * 0.5 }
            }
        }

        SequentialAnimation {
            id: scroll
            onFinished: st.nextPass()
            PauseAnimation { duration: 2000 }
            NumberAnimation {
                target: marquee
                property: "x"
                to: -st.overflow
                duration: Math.max(500, st.overflow / (st.u * 2.5) * 1000)
                easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 1500 }
            NumberAnimation {
                target: marquee
                property: "x"
                to: 0
                duration: 600
                easing.type: Easing.InOutSine
            }
        }

        function nextPass() {
            if (scrolls && (passesLeft > 0 || hovered)) {
                passesLeft = Math.max(0, passesLeft - 1);
                scroll.start();
            }
        }
        function restartScroll() {
            scroll.stop();
            marquee.x = 0;
            passesLeft = repeats;
            nextPass();
        }
        onScrollsChanged: restartScroll()
        onOverflowChanged: restartScroll()
        onResetKeyChanged: restartScroll()
        onHoveredChanged: if (hovered && !scroll.running) nextPass()
    }

    // style: 0 segmented, 1 solid, 2 thin line, 3 gradient
    component SegmentBar: Item {
        id: bar
        property real fraction: NaN
        property real u: 8
        property color tone: "cyan"
        property color primary: "cyan"
        property int style: 0
        readonly property real gap: Math.max(1, u * 0.14)
        readonly property int count: Math.max(8, Math.floor((width + gap) / (u * 0.6 + gap)))
        readonly property real segW: (width - gap * (count - 1)) / count
        readonly property int lit: isNaN(fraction) ? 0
                                   : Math.round(Math.max(0, Math.min(1, fraction)) * count)
        readonly property real fillW: isNaN(fraction) ? 0 : Math.round(width * Math.max(0, Math.min(1, fraction)))
        readonly property color track: Qt.rgba(primary.r, primary.g, primary.b, 0.12)
        readonly property color tip: Qt.lighter(tone, 1.35)
        readonly property real lineH: Math.max(2, Math.round(height * 0.35))

        Repeater {
            model: bar.style === 0 ? bar.count : 0
            Rectangle {
                required property int index
                x: index * (bar.segW + bar.gap)
                width: bar.segW
                height: bar.height
                color: index >= bar.lit ? bar.track
                       : index === bar.lit - 1 ? bar.tip : bar.tone
            }
        }

        Rectangle {
            visible: bar.style === 1 || bar.style === 3
            anchors.fill: parent
            color: bar.track
        }
        Rectangle {
            visible: bar.style === 1
            width: bar.fillW
            height: bar.height
            color: bar.tone
        }
        Rectangle {
            visible: bar.style === 3
            width: bar.fillW
            height: bar.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(bar.tone.r, bar.tone.g, bar.tone.b, 0.1) }
                GradientStop { position: 1; color: bar.tone }
            }
        }
        Rectangle {
            visible: (bar.style === 1 || bar.style === 3) && bar.fillW > 0
            x: bar.fillW - width
            width: Math.min(bar.fillW, Math.max(2, Math.round(bar.u * 0.25)))
            height: bar.height
            color: bar.tip
        }

        Rectangle {
            visible: bar.style === 2
            y: (bar.height - height) / 2
            width: bar.width
            height: Math.max(1, Math.round(bar.lineH / 2))
            color: Qt.rgba(bar.primary.r, bar.primary.g, bar.primary.b, 0.25)
        }
        Rectangle {
            visible: bar.style === 2
            y: (bar.height - height) / 2
            width: bar.fillW
            height: bar.lineH
            color: bar.tone
        }
        Rectangle {
            visible: bar.style === 2 && !isNaN(bar.fraction)
            width: bar.height
            height: bar.height
            radius: width / 2
            x: Math.max(0, Math.min(bar.width - width, bar.fillW - width / 2))
            color: bar.tip
        }
    }

    // Transport button: a drawn glyph (prev / play / pause / next) in a HUD box
    component HudButton: Item {
        id: btn
        property string glyph: "play"
        property color tone: "cyan"
        property bool highlighted: false        // main button: filled box
        signal clicked()

        opacity: enabled ? 1 : 0.3

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(btn.tone.r, btn.tone.g, btn.tone.b,
                           mouse.pressed ? 0.35 : mouse.containsMouse ? 0.2 : btn.highlighted ? 0.1 : 0)
            border.width: Math.max(1, btn.height * 0.04)
            border.color: Qt.rgba(btn.tone.r, btn.tone.g, btn.tone.b,
                                  mouse.containsMouse || btn.highlighted ? 0.9 : 0.35)
        }
        Canvas {
            id: icon
            anchors.centerIn: parent
            width: parent.height * 0.5
            height: width
            onWidthChanged: requestPaint()
            Connections {
                target: btn
                function onGlyphChanged() { icon.requestPaint(); }
                function onToneChanged() { icon.requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width, h = height;
                ctx.fillStyle = "rgba(" + Math.round(btn.tone.r * 255) + "," + Math.round(btn.tone.g * 255) + ","
                                + Math.round(btn.tone.b * 255) + ",1)";
                const tri = (x0, x1) => {       // triangle pointing left->right from x0 to x1
                    ctx.beginPath();
                    ctx.moveTo(x0, 0); ctx.lineTo(x1, h / 2); ctx.lineTo(x0, h);
                    ctx.closePath(); ctx.fill();
                };
                const triBack = (x0, x1) => {   // triangle pointing right->left
                    ctx.beginPath();
                    ctx.moveTo(x1, 0); ctx.lineTo(x0, h / 2); ctx.lineTo(x1, h);
                    ctx.closePath(); ctx.fill();
                };
                if (btn.glyph === "play") {
                    tri(w * 0.15, w * 0.9);
                } else if (btn.glyph === "pause") {
                    ctx.fillRect(w * 0.15, 0, w * 0.25, h);
                    ctx.fillRect(w * 0.6, 0, w * 0.25, h);
                } else if (btn.glyph === "next") {
                    tri(0, w * 0.75);
                    ctx.fillRect(w * 0.78, 0, w * 0.17, h);
                } else if (btn.glyph === "prev") {
                    ctx.fillRect(w * 0.05, 0, w * 0.17, h);
                    triBack(w * 0.25, w);
                } else if (btn.glyph === "shuffle") {
                    // two crossing arrows
                    ctx.strokeStyle = ctx.fillStyle;
                    ctx.lineWidth = Math.max(1, w * 0.1);
                    ctx.beginPath();
                    ctx.moveTo(0, h * 0.25); ctx.lineTo(w * 0.25, h * 0.25); ctx.lineTo(w * 0.65, h * 0.75); ctx.lineTo(w * 0.8, h * 0.75);
                    ctx.moveTo(0, h * 0.75); ctx.lineTo(w * 0.25, h * 0.75); ctx.lineTo(w * 0.65, h * 0.25); ctx.lineTo(w * 0.8, h * 0.25);
                    ctx.stroke();
                    for (const y of [h * 0.25, h * 0.75]) {
                        ctx.beginPath();
                        ctx.moveTo(w, y); ctx.lineTo(w * 0.72, y - h * 0.18); ctx.lineTo(w * 0.72, y + h * 0.18);
                        ctx.closePath(); ctx.fill();
                    }
                } else if (btn.glyph === "repeat" || btn.glyph === "repeat1") {
                    // loop with an arrowhead; "1" inside for repeat-track
                    ctx.strokeStyle = ctx.fillStyle;
                    ctx.lineWidth = Math.max(1, w * 0.1);
                    ctx.beginPath();
                    ctx.moveTo(w * 0.62, h * 0.2); ctx.lineTo(w * 0.1, h * 0.2); ctx.lineTo(w * 0.1, h * 0.8); ctx.lineTo(w * 0.35, h * 0.8);
                    ctx.moveTo(w * 0.38, h * 0.8); ctx.lineTo(w * 0.9, h * 0.8); ctx.lineTo(w * 0.9, h * 0.2); ctx.lineTo(w * 0.75, h * 0.2);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(w * 0.5, h * 0.8); ctx.lineTo(w * 0.32, h * 0.62); ctx.lineTo(w * 0.32, h * 0.98);
                    ctx.closePath(); ctx.fill();
                    if (btn.glyph === "repeat1") {
                        ctx.font = "bold " + Math.round(h * 0.5) + "px sans-serif";
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        ctx.fillText("1", w * 0.5, h * 0.5);
                    }
                }
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: btn.clicked()
        }
    }

    // Album art, or a drawn disc when the player gives none. Tinted to the neon
    // color in the "Neon tint" style.
    component AlbumArt: Item {
        id: art
        property string source
        property bool tinted: true
        property color tone: "cyan"
        property real u: 8
        property bool clickable: false
        signal clicked()

        MouseArea {
            anchors.fill: parent
            z: 1
            enabled: art.clickable
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: art.clicked()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(art.tone.r, art.tone.g, art.tone.b, 0.08)
            border.width: Math.max(1, art.u * 0.08)
            border.color: Qt.rgba(art.tone.r, art.tone.g, art.tone.b, 0.6)
        }
        Image {
            id: cover
            anchors.fill: parent
            anchors.margins: Math.max(1, art.u * 0.08)
            source: art.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            visible: status === Image.Ready
            layer.enabled: art.tinted
            // Full colorization already makes it a single-color image; don't also set
            // saturation to -1: that's applied after the tint and turns it grey again.
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: art.tone
                contrast: 0.25
            }
        }
        Canvas {
            anchors.fill: parent
            visible: cover.status !== Image.Ready
            onWidthChanged: requestPaint()
            onVisibleChanged: requestPaint()
            Connections {
                target: art
                function onToneChanged() { requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = Math.min(width, height) / 2;
                const rgba = a => "rgba(" + Math.round(art.tone.r * 255) + "," + Math.round(art.tone.g * 255) + ","
                                   + Math.round(art.tone.b * 255) + "," + a + ")";
                ctx.strokeStyle = rgba(0.7);
                ctx.lineWidth = Math.max(1, c * 0.05);
                for (const r of [0.7, 0.5, 0.3]) {
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, c * r, 0, Math.PI * 2);
                    ctx.stroke();
                }
                ctx.fillStyle = rgba(0.9);
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, c * 0.08, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    // ================= panel view =================
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real pixelSize: vertical ? width * 0.22 : height * 0.42

        Layout.minimumWidth: vertical ? 0 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? row.implicitHeight + Kirigami.Units.smallSpacing * 2 : 0
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.togglePlay();
            else
                root.expanded = !root.expanded;
        }
        onWheel: wheel => root.changeVolume(wheel.angleDelta.y > 0)

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: compact.pixelSize * 0.4

            Canvas {
                id: stateGlyph
                Layout.preferredWidth: compact.pixelSize * 0.8
                Layout.preferredHeight: compact.pixelSize * 0.8
                readonly property bool isPlaying: root.playing
                onIsPlayingChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    ctx.fillStyle = root.css(root.hasPlayer ? root.primary : root.withAlpha(root.primary, 0.4), 1);
                    if (isPlaying) {
                        ctx.beginPath(); ctx.moveTo(w * 0.15, 0); ctx.lineTo(w * 0.9, h / 2); ctx.lineTo(w * 0.15, h);
                        ctx.closePath(); ctx.fill();
                    } else {
                        ctx.fillRect(w * 0.15, 0, w * 0.25, h);
                        ctx.fillRect(w * 0.6, 0, w * 0.25, h);
                    }
                }
            }
            Text {
                visible: !compact.vertical && root.track !== ""
                Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                text: root.artist ? root.track + "  //  " + root.artist : root.track
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: compact.pixelSize
                color: root.primary
            }
        }
    }

    // ================= desktop / popup view =================
    fullRepresentation: Item {
        id: full

        // ---- size tiers ----
        //   tiny - title, artist, thin progress line, buttons (no header, art or volume)
        //   full - header, art + text side by side, progress, buttons, volume
        //   tall - big album art on top, everything else stacked under it
        //   wide - one strip: art | track info + progress | buttons + volume
        // Each tier sizes everything in units of u so it always fits the widget.
        readonly property real gu: Kirigami.Units.gridUnit
        readonly property string tier: {
            const w = width, h = height;
            if (w < gu * 12 || h < gu * 4.5) return "tiny";
            if (w / h >= 2.4) return "wide";
            if (h / w >= 1.15) return "tall";
            if (h < gu * 6.5) return "tiny";
            return "full";
        }
        readonly property bool tiny: tier === "tiny"
        readonly property bool wide: tier === "wide"
        readonly property bool tall: tier === "tall"
        readonly property bool showArt: !tiny && root.artStyle !== 2
        // a very short strip drops the header to make room
        readonly property bool showHeaderNow: !tiny && root.headerEnabled && !(wide && height < gu * 6)

        FontMetrics {
            id: fm
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: 100
        }
        readonly property real lineF: Math.max(1, fm.height / 100)

        // Heights and widths in units of u
        readonly property real gapU: 0.6
        readonly property real chromeU: tiny ? (0.4 + 0.25 + 0.4) * 2 : (0.4 + 0.5 + 0.9) * 2
        readonly property real headerU: showHeaderNow ? 0.85 * lineF + 1.15 : 0
        readonly property real textU: (1.3 + 0.9 + (root.showAlbum && !tiny ? 0.75 : 0)) * lineF
        readonly property real progressU: tiny ? 0.35 : 0.5 + 0.25 + 0.7 * lineF
        readonly property real controlsU: tiny ? 1.9 : 2.3
        readonly property bool showVolumeNow: !tiny && root.showVolume && root.hasVolume
        readonly property bool showShuffleRepeatNow: !tiny && root.showShuffleRepeat
        readonly property real volumeU: showVolumeNow ? Math.max(0.45, 0.65 * lineF) + gapU : 0
        readonly property real smallArtU: 5                         // full tier
        // tall tier: content as wide as the button row (or 12 units), art fills that width
        readonly property real tallArtU: Math.max(12, transportWidthU)
        // wide tier: one row as tall as the taller of (info + volume) and (buttons + progress)
        readonly property real wideRowU: Math.max(textU + volumeU, controlsU + gapU + progressU, 4.5)
        readonly property real transportWidthU: (showShuffleRepeatNow ? 2 * controlsU + 2 * 0.8 : 0)
                                                + (1.3 + 1.8 + 1.3) * controlsU + 2 * 0.8

        readonly property real neededU: (
              tall ? chromeU + headerU + (showArt ? tallArtU + gapU : 0) + textU + gapU + progressU + gapU + controlsU + volumeU
            : wide ? chromeU + headerU + wideRowU
            : chromeU + headerU + Math.max(showArt ? smallArtU : 0, textU) + gapU + progressU + gapU + controlsU + volumeU + gapU
            ) * 1.02
        readonly property real widthU: tiny ? 14
                                     : tall ? chromeU + tallArtU
                                     : wide ? chromeU + (showArt ? wideRowU + 1.0 : 0) + 12 + 1.0 + transportWidthU
                                     : 22
        readonly property real u: Math.max(3, Math.min(width / widthU, height / neededU))
        readonly property real pad: u * (tiny ? 0.4 : 0.9)
        readonly property real minText: 0
        function textSize(k) { return u * k; }

        Layout.preferredWidth: gu * 20
        // a new widget starts in the full layout, 20 grid units wide
        Layout.preferredHeight: Math.ceil(
            (chromeU + headerU + Math.max(showArt ? smallArtU : 0, textU) + gapU + progressU + gapU + controlsU + volumeU + gapU)
            * 1.02 * gu * 20 / 22)
        Layout.minimumWidth: gu * 8
        Layout.minimumHeight: gu * 4

        // long titles keep scrolling while the pointer is over the widget
        readonly property bool hovered: hover.hovered
        HoverHandler { id: hover }

        // Scroll anywhere on the widget to change the player's volume
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => root.changeVolume(event.angleDelta.y > 0)
        }
        // Middle-click anywhere to play/pause
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: root.togglePlay()
        }

        // Holo: dark backdrop that fades to transparent at the edges
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

        Item {
            id: frame
            anchors.fill: parent
            anchors.margins: Math.round(full.u * 0.4)
            readonly property real c: full.u * 1.6
        }

        Shape {
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

        Shape {
            id: brackets
            anchors.fill: frame
            visible: root.holo && root.borderEnabled
            layer.enabled: true
            layer.samples: 4
            readonly property real w: frame.width
            readonly property real h: frame.height
            readonly property real c: frame.c
            readonly property real arm: full.u * 1.8

            ShapePath {
                strokeColor: root.withAlpha(root.primary, 0.8)
                strokeWidth: Math.max(1, full.u * 0.12)
                fillColor: "transparent"
                joinStyle: ShapePath.MiterJoin
                capStyle: ShapePath.FlatCap

                startX: 0; startY: brackets.c + brackets.arm
                PathLine { x: 0;                           y: brackets.c }
                PathLine { x: brackets.c;                  y: 0 }
                PathLine { x: brackets.c + brackets.arm;   y: 0 }
                PathMove { x: brackets.w - brackets.arm;   y: 0 }
                PathLine { x: brackets.w;                  y: 0 }
                PathLine { x: brackets.w;                  y: brackets.arm }
                PathMove { x: brackets.w;                  y: brackets.h - brackets.c - brackets.arm }
                PathLine { x: brackets.w;                  y: brackets.h - brackets.c }
                PathLine { x: brackets.w - brackets.c;     y: brackets.h }
                PathLine { x: brackets.w - brackets.c - brackets.arm; y: brackets.h }
                PathMove { x: brackets.arm;                y: brackets.h }
                PathLine { x: 0;                           y: brackets.h }
                PathLine { x: 0;                           y: brackets.h - brackets.arm }
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

        // Blurred album art behind the content, fading out toward the edges
        Item {
            id: backdrop
            anchors.fill: frame
            anchors.margins: frame.c * 0.35
            visible: root.artBackdropOn && root.hasPlayer && root.artUrl !== "" && backdropImage.status === Image.Ready

            Image {
                id: backdropImage
                anchors.fill: parent
                source: root.artBackdropOn ? root.artUrl : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 128
                sourceSize.height: 128
                asynchronous: true
                visible: false
            }
            // soft-edged mask: opaque in the middle, transparent at the edges
            Canvas {
                id: backdropMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height, f = Math.min(w, h) * 0.3;
                    ctx.fillStyle = "white";
                    ctx.fillRect(0, 0, w, h);
                    ctx.globalCompositeOperation = "destination-out";
                    const edge = (x0, y0, x1, y1, rx, ry, rw, rh) => {
                        const g = ctx.createLinearGradient(x0, y0, x1, y1);
                        g.addColorStop(0, "rgba(0,0,0,1)");
                        g.addColorStop(1, "rgba(0,0,0,0)");
                        ctx.fillStyle = g;
                        ctx.fillRect(rx, ry, rw, rh);
                    };
                    edge(0, 0, f, 0, 0, 0, f, h);
                    edge(w, 0, w - f, 0, w - f, 0, f, h);
                    edge(0, 0, 0, f, 0, 0, w, f);
                    edge(0, h, 0, h - f, 0, h - f, w, f);
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: backdropImage
                blurEnabled: true
                blurMax: 64
                blur: 1.0
                brightness: -0.3
                saturation: 0.15
                opacity: 0.5
                maskEnabled: true
                maskSource: backdropMask
                maskThresholdMin: 0.0
                maskSpreadAtMin: 1.0
            }
        }

        // Slow sweeping scan band. Moved by a ~15 fps timer instead of an animation:
        // it's slow enough to look the same, and costs a quarter of the redraws.
        Timer {
            interval: 66
            repeat: true
            running: sweepArea.visible
            onTriggered: {
                const travel = sweepArea.height + sweepBand.height;
                sweepBand.y += travel / (6000 / interval);
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
                    GradientStop { position: 0.5; color: root.withAlpha(root.primary, 0.07) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // Content. Rendered through one effect: neon glow, or (Holo without glow)
        // a soft dark shadow that keeps text readable on bright wallpapers.
        Item {
            id: contentLayer
            anchors.fill: frame
            anchors.margins: Math.round(full.u * (full.tier === "tiny" ? 0.25 : 0.5))

            layer.enabled: root.glowEnabled || root.holo
            layer.effect: MultiEffect {
                blurMax: 24
                shadowEnabled: true
                shadowColor: root.glowEnabled ? root.primary : "black"
                shadowBlur: root.glowEnabled ? 0.45 : 0.8
                shadowOpacity: root.glowEnabled ? 0.75 : 0.6
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }

            // ---- sections (defined once, placed by the layouts below) ----
            Component {
                id: headerComp
                ColumnLayout {
                    spacing: full.u * 0.4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: full.u * 0.5

                        Rectangle {
                            Layout.preferredWidth: full.u * 0.45
                            Layout.preferredHeight: full.u * 0.45
                            color: root.accent
                            opacity: root.playing ? (root.blink ? 1 : 0.2) : 0.2
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "NOW.PLAYING"
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: full.textSize(0.85)
                            font.letterSpacing: full.u * 0.08
                            color: root.primary
                            opacity: 0.8
                        }
                        // Player name. With several players open it's also the switcher:
                        // click to cycle AUTO -> each player -> AUTO.
                        Text {
                            text: !root.hasPlayer ? "OFFLINE"
                                : root.paused ? (root.blink ? "PAUSED" : "")
                                : root.identity.toUpperCase()
                                    + (root.canSwitch ? (root.autoPlayer ? " [AUTO]" : " [LOCK]") : "")
                            font.family: root.fontFamily
                            font.pixelSize: full.textSize(0.85)
                            font.underline: switchArea.containsMouse
                            color: root.accent

                            MouseArea {
                                id: switchArea
                                anchors.fill: parent
                                enabled: root.canSwitch
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.nextPlayer()
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(2, full.u * 0.12)
                        Layout.topMargin: -full.u * 0.2
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
                }
            }
            Component {
                id: idleComp
                ColumnLayout {
                    spacing: full.u * 0.2
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "NO SIGNAL"
                        font.family: root.fontFamily
                        font.bold: true
                        font.letterSpacing: full.u * 0.15
                        font.pixelSize: full.textSize(full.tiny ? 1.2 : 1.8)
                        color: root.accent
                        opacity: root.blink ? 1 : 0.7
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "// NO MEDIA PLAYER"
                        font.family: root.fontFamily
                        font.pixelSize: full.textSize(0.75)
                        color: root.withAlpha(root.primary, 0.8)
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            // album art (click to bring the player's window to the front)
            Component {
                id: artComp
                AlbumArt {
                        source: root.artUrl
                        tinted: root.artStyle === 0
                        tone: root.primary
                        u: full.u
                        clickable: root.hasPlayer && root.player.canRaise
                        onClicked: root.raisePlayer()
                    }
            }
            // title, artist, album
            Component {
                id: infoComp
                    ColumnLayout {
                        spacing: 0

                        // Title and artist scroll when they're too long to fit, and restart
                        // together on each new track. The title glitches on track change.
                        ScrollText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.track || "UNKNOWN TRACK"
                            fontFamily: root.fontFamily
                            bold: true
                            pixelSize: full.textSize(1.3)
                            color: root.primary
                            u: full.u
                            resetKey: root.track
                            hovered: full.hovered
                            glitching: root.glitching
                            glitchX: root.glitchX
                            glitchColor: root.accent
                        }
                        ScrollText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: root.artist !== ""
                            text: root.artist.toUpperCase()
                            fontFamily: root.fontFamily
                            bold: true
                            letterSpacing: full.u * 0.04
                            pixelSize: full.textSize(0.9)
                            color: root.accent
                            u: full.u
                            resetKey: root.track
                            hovered: full.hovered
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: root.showAlbum && !full.tiny && root.album !== ""
                            text: root.album
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: full.textSize(0.75)
                            color: root.withAlpha(root.primary, 0.8)
                        }
                    }
            }
            // progress: click or drag to seek (with a time preview); click the
            // track length to switch to time left
            Component {
                id: progressComp
                ColumnLayout {
                    id: prog
                    spacing: full.u * 0.25

                    // while dragging, the bar shows where you'll land; the seek happens on release
                    property bool dragging: false
                    property real dragFraction: 0
                    readonly property real liveFraction: root.lengthUs > 0 ? root.positionUs / root.lengthUs : 0
                    function clamp(f) { return Math.max(0, Math.min(1, f)); }

                    SegmentBar {
                        id: progress
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(2, full.u * (full.tiny ? 0.35 : 0.5))
                        fraction: prog.dragging ? prog.dragFraction : prog.liveFraction
                        u: full.u * (full.tiny ? 0.6 : 1)
                        tone: prog.dragging ? root.accent : root.primary
                        primary: root.primary
                        style: root.progressBarStyle

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.topMargin: -full.u * 0.3       // easier to hit
                            anchors.bottomMargin: -full.u * 0.3
                            enabled: root.canSeek
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => {
                                prog.dragFraction = prog.clamp(mouse.x / width);
                                prog.dragging = true;
                            }
                            onPositionChanged: mouse => {
                                if (pressed)
                                    prog.dragFraction = prog.clamp(mouse.x / width);
                            }
                            onReleased: {
                                if (prog.dragging)
                                    root.seekTo(prog.dragFraction);
                                prog.dragging = false;
                            }
                            onCanceled: prog.dragging = false
                        }

                        // floating time label: where you'll land (dragging) or what's under the pointer
                        Rectangle {
                            id: preview
                            readonly property real at: prog.dragging ? prog.dragFraction
                                                       : seekArea.containsMouse ? prog.clamp(seekArea.mouseX / progress.width) : 0
                            visible: root.canSeek && (prog.dragging || seekArea.containsMouse)
                            width: previewText.implicitWidth + full.u * 0.6
                            height: previewText.implicitHeight + full.u * 0.2
                            x: Math.max(0, Math.min(progress.width - width, at * progress.width - width / 2))
                            y: -height - full.u * 0.35
                            z: 10
                            color: Qt.rgba(0.02, 0.02, 0.07, 0.9)
                            border.width: 1
                            border.color: prog.dragging ? root.accent : root.withAlpha(root.primary, 0.6)
                            Text {
                                id: previewText
                                anchors.centerIn: parent
                                text: root.clock(preview.at * root.lengthUs)
                                font.family: root.fontFamily
                                font.features: { "tnum": 1 }
                                font.pixelSize: full.textSize(0.65)
                                color: prog.dragging ? root.accent : root.primary
                            }
                        }
                    }
                    RowLayout {
                        visible: !full.tiny
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: root.clock(prog.dragging ? prog.dragFraction * root.lengthUs : root.positionUs)
                            font.family: root.fontFamily
                            font.features: { "tnum": 1 }
                            font.pixelSize: full.textSize(0.7)
                            color: prog.dragging ? root.accent : root.withAlpha(root.primary, 0.85)
                        }
                        // track length, or time left; click to switch
                        Text {
                            readonly property real shownPos: prog.dragging ? prog.dragFraction * root.lengthUs : root.positionUs
                            text: root.lengthUs <= 0 ? "--:--"
                                : root.showRemaining ? "-" + root.clock(Math.max(0, root.lengthUs - shownPos))
                                : root.clock(root.lengthUs)
                            font.family: root.fontFamily
                            font.features: { "tnum": 1 }
                            font.pixelSize: full.textSize(0.7)
                            font.underline: lengthArea.containsMouse
                            color: root.withAlpha(root.primary, 0.85)
                            MouseArea {
                                id: lengthArea
                                anchors.fill: parent
                                anchors.margins: -full.u * 0.2
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleRemaining()
                            }
                        }
                    }
                }
            }
            // transport: [shuffle] prev play next [repeat]
            Component {
                id: transportComp
                RowLayout {
                    spacing: full.u * 0.8

                    HudButton {
                        visible: full.showShuffleRepeatNow && root.canShuffle
                        Layout.preferredWidth: full.u * full.controlsU
                        Layout.preferredHeight: full.u * full.controlsU * 0.8
                        Layout.alignment: Qt.AlignVCenter
                        glyph: "shuffle"
                        tone: root.shuffleOn ? root.accent : root.withAlpha(root.primary, 0.55)
                        highlighted: root.shuffleOn
                        onClicked: root.toggleShuffle()
                    }
                    HudButton {
                        Layout.preferredWidth: full.u * full.controlsU * 1.3
                        Layout.preferredHeight: full.u * full.controlsU
                        glyph: "prev"
                        tone: root.primary
                        enabled: root.hasPlayer && root.player.canGoPrevious
                        onClicked: root.previous()
                    }
                    HudButton {
                        Layout.preferredWidth: full.u * full.controlsU * 1.8
                        Layout.preferredHeight: full.u * full.controlsU
                        glyph: root.playing ? "pause" : "play"
                        tone: root.accent
                        highlighted: true
                        enabled: root.hasPlayer && root.player.canControl
                        onClicked: root.togglePlay()
                    }
                    HudButton {
                        Layout.preferredWidth: full.u * full.controlsU * 1.3
                        Layout.preferredHeight: full.u * full.controlsU
                        glyph: "next"
                        tone: root.primary
                        enabled: root.hasPlayer && root.player.canGoNext
                        onClicked: root.next()
                    }
                    HudButton {
                        visible: full.showShuffleRepeatNow && root.canLoop
                        readonly property bool on: root.loopStatus === Mpris.LoopStatus.Playlist
                                                   || root.loopStatus === Mpris.LoopStatus.Track
                        Layout.preferredWidth: full.u * full.controlsU
                        Layout.preferredHeight: full.u * full.controlsU * 0.8
                        Layout.alignment: Qt.AlignVCenter
                        glyph: root.loopStatus === Mpris.LoopStatus.Track ? "repeat1" : "repeat"
                        tone: on ? root.accent : root.withAlpha(root.primary, 0.55)
                        highlighted: on
                        onClicked: root.cycleLoop()
                    }
                }
            }
            // volume (click or drag to set; scrolling also works)
            Component {
                id: volumeComp
                RowLayout {
                    spacing: full.u * 0.5

                    Text {
                        text: "VOL"
                        font.family: root.fontFamily
                        font.pixelSize: full.textSize(0.65)
                        color: root.withAlpha(root.primary, 0.8)
                    }
                    SegmentBar {
                        id: volumeBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(2, full.u * 0.45)
                        fraction: root.volume
                        u: full.u * 0.7
                        tone: root.accent
                        primary: root.primary
                        style: root.volumeBarStyle

                        MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -full.u * 0.3        // easier to hit
                            anchors.bottomMargin: -full.u * 0.3
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => root.setVolume(mouse.x / width)
                            onPositionChanged: mouse => { if (pressed) root.setVolume(mouse.x / width); }
                        }
                    }
                    Text {
                        Layout.preferredWidth: full.u * 2.4
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.volume * 100) + "%"
                        font.family: root.fontFamily
                        font.features: { "tnum": 1 }
                        font.pixelSize: full.textSize(0.65)
                        color: root.withAlpha(root.primary, 0.8)
                    }
                }
            }

            // ================= stacked layout: tiny / full / tall =================
            ColumnLayout {
                id: content
                visible: !full.wide
                anchors.fill: parent
                anchors.margins: full.pad
                spacing: full.u * full.gapU

                Loader {
                    Layout.fillWidth: true
                    active: !full.wide && full.showHeaderNow
                    visible: active
                    sourceComponent: headerComp
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: !full.wide && !root.hasPlayer
                    visible: active
                    sourceComponent: idleComp
                }
                // tall: big art on top
                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: full.u * full.tallArtU
                    Layout.preferredHeight: full.u * full.tallArtU
                    active: full.tall && full.showArt && root.hasPlayer
                    visible: active
                    sourceComponent: artComp
                }
                // full: small art beside the text; tiny / tall: text only
                RowLayout {
                    visible: root.hasPlayer
                    Layout.fillWidth: true
                    spacing: full.u * 0.8
                    Loader {
                        Layout.preferredWidth: full.u * full.smallArtU
                        Layout.preferredHeight: full.u * full.smallArtU
                        Layout.alignment: Qt.AlignVCenter
                        active: full.tier === "full" && full.showArt && root.hasPlayer
                        visible: active
                        sourceComponent: artComp
                    }
                    Loader {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        active: !full.wide && root.hasPlayer
                        sourceComponent: infoComp
                    }
                }
                Loader {
                    Layout.fillWidth: true
                    active: !full.wide && root.hasPlayer
                    visible: active
                    sourceComponent: progressComp
                }
                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: !full.wide && root.hasPlayer
                    visible: active
                    sourceComponent: transportComp
                }
                Loader {
                    Layout.fillWidth: true
                    active: !full.wide && root.hasPlayer && full.showVolumeNow
                    visible: active
                    sourceComponent: volumeComp
                }
                // Absorb extra height so rows stay packed at the top
                Item { Layout.fillHeight: true; visible: root.hasPlayer }
            }

            // ================= wide layout: art | info + volume | buttons + progress =================
            ColumnLayout {
                visible: full.wide
                anchors.fill: parent
                anchors.margins: full.pad
                spacing: full.u * full.gapU

                Loader {
                    Layout.fillWidth: true
                    active: full.wide && full.showHeaderNow
                    visible: active
                    sourceComponent: headerComp
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: full.wide && !root.hasPlayer
                    visible: active
                    sourceComponent: idleComp
                }
                RowLayout {
                    visible: root.hasPlayer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: full.u * 1.0

                    Loader {
                        Layout.preferredWidth: full.u * full.wideRowU
                        Layout.preferredHeight: full.u * full.wideRowU
                        Layout.alignment: Qt.AlignVCenter
                        active: full.wide && full.showArt && root.hasPlayer
                        visible: active
                        sourceComponent: artComp
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: full.u * full.gapU
                        Loader {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            active: full.wide && root.hasPlayer
                            sourceComponent: infoComp
                        }
                        Loader {
                            Layout.fillWidth: true
                            active: full.wide && root.hasPlayer && full.showVolumeNow
                            visible: active
                            sourceComponent: volumeComp
                        }
                    }
                    // buttons + progress: as wide as the buttons, so the title gets the rest
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: full.u * full.transportWidthU
                        Layout.maximumWidth: full.u * full.transportWidthU
                        spacing: full.u * full.gapU
                        Loader {
                            Layout.alignment: Qt.AlignHCenter
                            active: full.wide && root.hasPlayer
                            sourceComponent: transportComp
                        }
                        Loader {
                            Layout.fillWidth: true
                            active: full.wide && root.hasPlayer
                            sourceComponent: progressComp
                        }
                    }
                }
            }
        }

        Canvas {
            anchors.fill: frame
            anchors.margins: frame.c * 0.5
            visible: root.scanlinesEnabled
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = "rgba(0, 0, 0, 0.18)";
                for (let y = 0; y < height; y += 3)
                    ctx.fillRect(0, y, width, 1);
            }
        }
    }
}
