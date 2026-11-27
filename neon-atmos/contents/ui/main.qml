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
    readonly property string locationName: Plasmoid.configuration.locationName
    readonly property bool hasLocation: locationName !== ""
    // "Berlin, State of Berlin, Germany" -> "BERLIN"
    readonly property string placeShort: locationName.split(",")[0].trim().toUpperCase()
    readonly property bool showCity: Plasmoid.configuration.showCity && hasLocation
    // Units. "Automatic" follows the system locale: °F in the US; mph wind in the US and UK.
    readonly property int localeSystem: Qt.locale().measurementSystem
    readonly property bool fahrenheit: Plasmoid.configuration.tempUnit === 2
        || (Plasmoid.configuration.tempUnit === 0 && localeSystem === Locale.ImperialUSSystem)
    readonly property int windUnit: Plasmoid.configuration.windUnit > 0 ? Plasmoid.configuration.windUnit - 1
        : (localeSystem === Locale.ImperialUSSystem || localeSystem === Locale.ImperialUKSystem) ? 2 : 0
    readonly property bool showDetails: Plasmoid.configuration.showDetails
    readonly property bool showHourly: Plasmoid.configuration.showHourly
    readonly property bool showDaily: Plasmoid.configuration.showDaily
    readonly property int dailyDays: Plasmoid.configuration.dailyDays
    readonly property int refreshMinutes: Plasmoid.configuration.refreshMinutes

    readonly property bool holo: Plasmoid.configuration.style === 1
    readonly property bool borderEnabled: Plasmoid.configuration.showBorder
    readonly property bool headerEnabled: Plasmoid.configuration.showHeader
    readonly property bool glowEnabled: Plasmoid.configuration.glow
    readonly property bool scanlinesEnabled: Plasmoid.configuration.scanlines
    readonly property bool sweepEnabled: Plasmoid.configuration.scanSweep
    readonly property color primary: Plasmoid.configuration.primaryColor
    readonly property color accent: Plasmoid.configuration.accentColor
    readonly property color critical: Plasmoid.configuration.criticalColor
    readonly property real backgroundAlpha: Plasmoid.configuration.backgroundOpacity / 100
    readonly property string fontFamily: Plasmoid.configuration.fontFamily || "monospace"

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                 || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The full view is on screen: always on the desktop, only while the popup is open in a panel
    readonly property bool fullShown: !inPanel || expanded

    // ---------- weather data (Open-Meteo) ----------
    readonly property var windUnits: [
        { api: "kmh", label: "KM/H" }, { api: "ms", label: "M/S" },
        { api: "mph", label: "MPH" },  { api: "kn", label: "KN" }
    ]

    // Coordinates are rounded to 2 decimals (about 1 km) before they're sent.
    readonly property string requestUrl: !hasLocation ? "" :
        "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + Plasmoid.configuration.latitude.toFixed(2)
        + "&longitude=" + Plasmoid.configuration.longitude.toFixed(2)
        + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,"
        + "wind_speed_10m,wind_direction_10m,surface_pressure"
        + "&hourly=temperature_2m,precipitation_probability"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
        + "&timezone=auto&forecast_days=7"
        + "&temperature_unit=" + (fahrenheit ? "fahrenheit" : "celsius")
        + "&wind_speed_unit=" + windUnits[windUnit].api

    property var wx: null            // last good response
    property bool loading: false
    property bool failed: false      // last request failed (old data, if any, is kept)
    property var lastSync: null
    property var pendingRequest: null

    function fetch() {
        if (!requestUrl)
            return;
        if (pendingRequest)
            pendingRequest.abort();
        const url = requestUrl;
        const xhr = new XMLHttpRequest();
        pendingRequest = xhr;
        loading = true;
        requestTimeout.restart();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || pendingRequest !== xhr)
                return;
            pendingRequest = null;
            loading = false;
            requestTimeout.stop();
            let data = null;
            try {
                if (xhr.status === 200)
                    data = JSON.parse(xhr.responseText);
            } catch (e) {
                data = null;
            }
            if (data && data.current && data.hourly && data.daily && url === requestUrl) {
                wx = data;
                failed = false;
                lastSync = new Date();
                retryTimer.stop();
            } else {
                failed = true;
                retryTimer.restart();
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    Timer {
        id: refreshTimer
        interval: root.refreshMinutes * 60000
        repeat: true
        running: root.hasLocation
        onTriggered: root.fetch()
    }
    // After a failed request, try again in a minute instead of waiting a full refresh
    Timer {
        id: retryTimer
        interval: 60000
        onTriggered: root.fetch()
    }
    Timer {
        id: requestTimeout
        interval: 20000
        onTriggered: {
            if (root.pendingRequest) {
                root.pendingRequest.abort();
                root.pendingRequest = null;
            }
            root.loading = false;
            root.failed = true;
            retryTimer.restart();
        }
    }
    Component.onCompleted: fetch()
    // New location or units: drop the old data so nothing shows in the wrong place/unit
    onRequestUrlChanged: {
        wx = null;
        failed = false;
        retryTimer.stop();
        fetch();
        refreshTimer.restart();
    }

    // Shared blink phase. Only runs when there's something to signal (loading,
    // connection lost, storm) and the full view is on screen; otherwise the header
    // light stays steady.
    readonly property bool alerting: loading || failed || storm
    property bool blink: false
    Timer {
        interval: 500
        repeat: true
        running: root.fullShown && root.alerting
        onRunningChanged: if (!running) root.blink = false
        onTriggered: root.blink = !root.blink
    }

    // ---------- derived values ----------
    readonly property var cur: wx ? wx.current : null
    readonly property bool isDay: cur ? cur.is_day === 1 : true
    readonly property bool storm: cur ? cur.weather_code >= 95 : false

    // Next 24 hours, starting at the current hour
    readonly property var hours: {
        if (!wx)
            return [];
        const h = wx.hourly;
        let i = h.time.indexOf(wx.current.time.slice(0, 13) + ":00");
        if (i < 0)
            i = 0;
        const out = [];
        for (let k = i; k < Math.min(i + 25, h.time.length); k++)
            out.push({ temp: h.temperature_2m[k], precip: h.precipitation_probability[k] || 0 });
        return out;
    }

    readonly property var days: {
        if (!wx)
            return [];
        const d = wx.daily;
        const out = [];
        for (let i = 0; i < Math.min(dailyDays, d.time.length); i++) {
            out.push({
                name: i === 0 ? "TODAY" : Qt.formatDate(new Date(d.time[i] + "T12:00"), "ddd").toUpperCase(),
                code: d.weather_code[i],
                max: d.temperature_2m_max[i],
                min: d.temperature_2m_min[i],
                precip: d.precipitation_probability_max[i] || 0
            });
        }
        return out;
    }

    // ---------- helpers ----------
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + a + ")";
    }
    function deg(t) { return (t === undefined || t === null || isNaN(t)) ? "--°" : Math.round(t) + "°"; }
    function compass(d) { return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(d / 45) % 8]; }
    function clock(iso) { return iso ? iso.slice(11, 16) : "--:--"; }

    // WMO weather codes -> HUD text
    function condition(code) {
        if (code === 0) return "CLEAR";
        if (code === 1) return "MOSTLY CLEAR";
        if (code === 2) return "PARTLY CLOUDY";
        if (code === 3) return "OVERCAST";
        if (code === 45 || code === 48) return "FOG";
        if (code >= 51 && code <= 55) return "DRIZZLE";
        if (code === 56 || code === 57) return "FREEZING DRIZZLE";
        if (code === 61) return "LIGHT RAIN";
        if (code === 63) return "RAIN";
        if (code === 65) return "HEAVY RAIN";
        if (code === 66 || code === 67) return "FREEZING RAIN";
        if (code === 71) return "LIGHT SNOW";
        if (code === 73) return "SNOW";
        if (code === 75) return "HEAVY SNOW";
        if (code === 77) return "SNOW GRAINS";
        if (code >= 80 && code <= 82) return "RAIN SHOWERS";
        if (code === 85 || code === 86) return "SNOW SHOWERS";
        if (code === 95) return "THUNDERSTORM";
        if (code === 96 || code === 99) return "STORM + HAIL";
        return "UNKNOWN";
    }
    // WMO weather codes -> which glyph to draw (see WxGlyph)
    function glyphKind(code, day) {
        if (code <= 1) return day ? "clear-day" : "clear-night";
        if (code === 2) return day ? "partly-day" : "partly-night";
        if (code === 3) return "cloudy";
        if (code === 45 || code === 48) return "fog";
        if (code >= 51 && code <= 55) return "drizzle";
        if (code === 56 || code === 57 || code === 66 || code === 67) return "freezing";
        if ((code >= 61 && code <= 65) || (code >= 80 && code <= 82)) return "rain";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
        if (code >= 95) return "storm";
        return "cloudy";
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: hasLocation ? locationName : i18n("Weather")
    toolTipSubText: !hasLocation ? i18n("No location set")
                  : cur ? deg(cur.temperature_2m) + (fahrenheit ? "F" : "C") + "  ·  " + condition(cur.weather_code)
                  : failed ? i18n("Can't reach the weather service") : i18n("Loading…")

    // Note: inline components can't see ids from this file (like `root`),
    // so anything that depends on root is set where they're used.

    // Neon line-art weather glyph, drawn on a 100x100 grid and scaled to fit.
    // Drawn instead of using theme icons so it matches the HUD in any icon theme.
    component WxGlyph: Canvas {
        id: glyph
        property string kind: "cloudy"
        property color tint: "cyan"

        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function rgba(a) {
            return "rgba(" + Math.round(tint.r * 255) + "," + Math.round(tint.g * 255) + ","
                   + Math.round(tint.b * 255) + "," + a + ")";
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const size = Math.min(width, height);
            if (size <= 0)
                return;
            ctx.translate((width - size) / 2, (height - size) / 2);
            ctx.scale(size / 100, size / 100);
            ctx.lineWidth = Math.max(4.5, 1.3 * 100 / size);   // at least ~1.3 px
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.strokeStyle = rgba(1);

            const k = kind;
            const hasCloud = !(k === "clear-day" || k === "clear-night");
            const partly = k === "partly-day" || k === "partly-night";

            function sun(cx, cy, r) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.fillStyle = rgba(0.22);
                ctx.fill();
                ctx.stroke();
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(a) * r * 1.45, cy + Math.sin(a) * r * 1.45);
                    ctx.lineTo(cx + Math.cos(a) * r * 1.9, cy + Math.sin(a) * r * 1.9);
                    ctx.stroke();
                }
            }
            function moon(cx, cy, r) {
                const ox = cx + r * 0.55, oy = cy - r * 0.45, orr = r * 0.85;
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.fillStyle = rgba(0.22);
                ctx.fill();
                ctx.stroke();
                // bite out the crescent, then outline the bite inside the disc
                ctx.save();
                ctx.globalCompositeOperation = "destination-out";
                ctx.beginPath();
                ctx.arc(ox, oy, orr, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
                ctx.save();
                ctx.beginPath();
                ctx.arc(cx, cy, r + 3, 0, Math.PI * 2);
                ctx.clip();
                ctx.beginPath();
                ctx.arc(ox, oy, orr, 0, Math.PI * 2);
                ctx.stroke();
                ctx.restore();
            }
            function cloudPath() {
                ctx.beginPath();
                ctx.moveTo(26, 70);
                ctx.bezierCurveTo(13, 70, 13, 52, 27, 53);
                ctx.bezierCurveTo(28, 36, 52, 32, 58, 46);
                ctx.bezierCurveTo(64, 38, 80, 42, 78, 55);
                ctx.bezierCurveTo(90, 56, 89, 70, 77, 70);
                ctx.closePath();
            }

            if (k === "clear-day") sun(50, 50, 17);
            else if (k === "clear-night") moon(48, 52, 26);
            else if (k === "partly-day") sun(36, 34, 11);
            else if (k === "partly-night") moon(36, 34, 15);

            if (hasCloud) {
                // clear what's behind the cloud so the sun/moon sits behind it
                ctx.save();
                cloudPath();
                ctx.globalCompositeOperation = "destination-out";
                ctx.fill();
                ctx.restore();
                cloudPath();
                ctx.fillStyle = rgba(partly ? 0.15 : 0.22);
                ctx.fill();
                ctx.stroke();
            }

            // what's falling out of it
            const line = (x1, y1, x2, y2) => { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); };
            const flake = (x, y, r) => { for (let i = 0; i < 3; i++) { const a = i * Math.PI / 3; line(x - Math.cos(a) * r, y - Math.sin(a) * r, x + Math.cos(a) * r, y + Math.sin(a) * r); } };
            if (k === "rain") {
                for (let i = 0; i < 3; i++) line(38 + i * 13, 79, 33 + i * 13, 93);
            } else if (k === "drizzle") {
                for (let i = 0; i < 3; i++) { line(38 + i * 13, 79, 36 + i * 13, 83); line(35 + i * 13, 89, 33 + i * 13, 93); }
            } else if (k === "freezing") {
                line(38, 79, 33, 93); line(64, 79, 59, 93); flake(50, 86, 5);
            } else if (k === "snow") {
                flake(36, 84, 6); flake(52, 88, 6); flake(68, 84, 6);
            } else if (k === "storm") {
                ctx.beginPath();
                ctx.moveTo(56, 74); ctx.lineTo(45, 87); ctx.lineTo(54, 87); ctx.lineTo(47, 98);
                ctx.stroke();
            } else if (k === "fog") {
                line(20, 80, 70, 80); line(30, 88, 82, 88); line(22, 96, 62, 96);
            }
        }
    }

    component Readout: RowLayout {
        id: readout
        property string label
        property string value
        property color primary: "cyan"
        property string fontFamily: "monospace"
        property real pixelSize: 10
        spacing: pixelSize * 0.6

        Text {
            text: readout.label
            font.family: readout.fontFamily
            font.pixelSize: readout.pixelSize
            color: Qt.rgba(readout.primary.r, readout.primary.g, readout.primary.b, 0.75)
            Layout.preferredWidth: readout.pixelSize * 3.4
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: readout.value
            font.family: readout.fontFamily
            font.features: { "tnum": 1 }
            font.pixelSize: readout.pixelSize
            font.bold: true
            color: readout.primary
        }
    }

    // ================= panel view =================
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real pixelSize: vertical ? width * 0.28 : height * 0.5

        Layout.minimumWidth: vertical ? 0 : row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? row.implicitHeight + Kirigami.Units.smallSpacing * 2 : 0
        onClicked: root.expanded = !root.expanded

        GridLayout {
            id: row
            anchors.centerIn: parent
            flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: compact.vertical ? -1 : 1
            columns: compact.vertical ? 1 : -1
            columnSpacing: compact.pixelSize * 0.3
            rowSpacing: 0

            WxGlyph {
                Layout.preferredWidth: compact.pixelSize * 1.4
                Layout.preferredHeight: compact.pixelSize * 1.4
                Layout.alignment: Qt.AlignHCenter
                kind: root.cur ? root.glyphKind(root.cur.weather_code, root.isDay) : "cloudy"
                tint: root.storm ? root.critical : root.primary
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.cur ? root.deg(root.cur.temperature_2m) : (root.hasLocation ? "--°" : "N/A")
                font.family: root.fontFamily
                font.bold: true
                font.features: { "tnum": 1 }
                font.pixelSize: compact.pixelSize
                color: root.storm ? root.critical : root.primary
            }
        }
    }

    // ================= desktop / popup view =================
    fullRepresentation: Item {
        id: full

        // ---- size tiers ----
        // The layout changes with the widget's size (in grid units, so display
        // scaling doesn't matter):
        //   tiny - glyph, temperature and condition only, no header
        //   full - header, current conditions, then the sections that are turned on
        //   wide - the same sections side by side
        // Sections you turn on are always shown: everything shrinks to fit them.
        // Only if the text would get too small to read is a section dropped
        // (24h graph first, then readouts, then the forecast).
        readonly property real gu: Kirigami.Units.gridUnit
        readonly property string tier:
            (width < gu * 11 || height < gu * 5) ? "tiny"
            : width / height >= 2.4 ? "wide"
            : "full"

        // Font metrics turn font sizes (in u) into real heights and widths
        FontMetrics {
            id: fm
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: 100
        }
        readonly property real lineF: Math.max(1, fm.height / 100)
        readonly property real charF: Math.max(0.4, fm.averageCharacterWidth / 100)

        // Smallest scale that stays readable (smallest text is 0.6 u)
        readonly property real minU: gu * 0.85
        readonly property real gapU: 0.6
        readonly property real chromeU: (0.4 + 0.5 + 0.9) * 2       // frame + effect padding + margins

        // Section sizes in units of u (the small constants are line spacing, checked
        // against measured layouts)
        readonly property real headerU: root.headerEnabled ? 0.85 * lineF + 0.62 + gapU : 0
        readonly property real currentU: Math.max(3.8, (root.showCity ? 0.7 * lineF : 0) + (3.2 + 0.8) * lineF + 0.12)
        readonly property real detailsRowsU: 3 * 0.7 * lineF + 2 * 0.15 + 0.2     // stacked: 2 columns, 3 rows
        readonly property real hourlyU: 0.7 * lineF + 0.2 + 4.2 + 0.11
        readonly property real dailyU: (0.72 + 0.8 + 0.72 + 0.66) * lineF + 1.9 + 0.3 + 0.31
        // wide strip: widths of each section
        readonly property real currentW: 3.8 + 0.8 + (4 * 3.2 + 0.95) * charF + 0.15 + 0.8 + (2 * 0.7 + 4 * 1.0) * charF + 0.35
        readonly property real detailsW: 3.4 * 0.7 + 0.42 + 11 * 0.7 * charF
        readonly property real hourlyW: 8
        readonly property real dailyW: root.dailyDays * 3.2 + (root.dailyDays - 1) * 0.3
        readonly property real sectionGapW: 2.05                      // gap + divider line + gap
        readonly property real wideDetailsH: 5 * 0.7 * lineF + 4 * 0.15 + 0.3   // 1 column, 5 rows

        // Choose the scale with every enabled section; drop sections (lowest
        // priority first) only while the scale is below readable.
        function plan(sizeOf, total) {
            const keep = { daily: root.showDaily, details: root.showDetails, hourly: root.showHourly };
            let u = total(keep);
            for (const k of ["hourly", "details", "daily"]) {
                if (u >= minU)
                    break;
                if (keep[k]) {
                    keep[k] = false;
                    u = total(keep);
                }
            }
            return { u: u, keep: keep };
        }
        readonly property var stackPlan: plan(null, keep => {
            let h = chromeU + headerU + currentU;
            if (keep.details) h += gapU + detailsRowsU;
            if (keep.hourly) h += gapU + hourlyU;
            if (keep.daily) h += gapU + dailyU;
            return Math.min(width / 22, height / (h * 1.03));
        })
        readonly property var widePlan: plan(null, keep => {
            let w = chromeU + currentW, h = currentU;
            if (keep.details) { w += sectionGapW + detailsW; h = Math.max(h, wideDetailsH); }
            if (keep.hourly)  { w += sectionGapW + hourlyW;  h = Math.max(h, 4); }
            if (keep.daily)   { w += sectionGapW + dailyW;   h = Math.max(h, dailyU); }
            return Math.min(width / (w * 1.03), height / ((chromeU + headerU + h) * 1.03));
        })

        readonly property real u: Math.max(3,
              tier === "tiny" ? Math.min(width / 13, height / (root.showCity ? 7.2 : 6.4))
            : tier === "wide" ? widePlan.u
            : stackPlan.u)
        // the planner keeps text readable, so no fixed minimum except in the tiny layout
        readonly property real minText: tier === "tiny" ? gu * 0.5 : 0
        function textSize(k) { return Math.max(minText, u * k); }
        readonly property real pad: u * (tier === "tiny" ? 0.4 : 0.9)

        Layout.preferredWidth: gu * 20
        Layout.preferredHeight: gu * 26
        Layout.minimumWidth: gu * 7
        Layout.minimumHeight: gu * 3.5

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
            anchors.margins: full.u * 0.4
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
            anchors.margins: full.u * (full.tier === "tiny" ? 0.25 : 0.5)

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


            // ---- sections (defined once, placed by the tier layouts below) ----
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
                                color: root.failed ? root.critical : root.accent
                                opacity: root.alerting ? (root.blink ? 1 : 0.2) : 1
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "ATMOS"
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: full.textSize(0.85)
                                font.letterSpacing: full.u * 0.08
                                color: root.primary
                                opacity: 0.8
                            }
                            Text {
                                text: !root.hasLocation ? "OFFLINE"
                                    : root.failed ? "LINK LOST"
                                    : root.loading && !root.wx ? "UPLINK…"
                                    : root.lastSync ? "SYNC " + Qt.formatTime(root.lastSync, "hh:mm") : ""
                                font.family: root.fontFamily
                                font.pixelSize: full.textSize(0.85)
                                color: root.failed ? root.critical : root.accent
                            }
                        }
                        Item {
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
                }
            }

            // No data yet / no location / request failed
            Component {
                id: messageComp
                Text {
                    readonly property bool tiny: full.tier === "tiny"
                    text: !root.hasLocation ? (tiny ? "NO LOCATION" : "NO LOCATION SET\n// CONFIGURE WIDGET")
                        : root.failed ? (tiny ? "LINK LOST" : "UPLINK FAILED\n// RETRYING")
                        : (tiny ? "UPLINK…" : "ESTABLISHING UPLINK…")
                    font.family: root.fontFamily
                    font.pixelSize: full.textSize(0.9)
                    color: root.failed || !root.hasLocation ? root.accent : root.primary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }

            Component {
                id: currentComp
                RowLayout {
                    readonly property bool tiny: full.tier === "tiny"
                    spacing: full.u * (tiny ? 0.5 : 0.8)

                    WxGlyph {
                        Layout.preferredWidth: full.u * (parent.tiny ? 3.0 : 3.8)
                        Layout.preferredHeight: full.u * (parent.tiny ? 3.0 : 3.8)
                        Layout.alignment: Qt.AlignVCenter
                        kind: root.cur ? root.glyphKind(root.cur.weather_code, root.isDay) : "cloudy"
                        tint: root.storm ? root.critical : root.primary
                    }

                    // Temperature + condition. Takes the leftover width; the
                    // condition text elides rather than pushing the layout wider.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                            visible: root.showCity
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.placeShort
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.bold: true
                            font.letterSpacing: full.u * 0.08
                            font.pixelSize: full.textSize(full.tier === "tiny" ? 0.6 : 0.7)
                            color: root.withAlpha(root.primary, 0.85)
                        }

                        RowLayout {
                            spacing: full.u * 0.15
                            Text {
                                text: root.cur ? root.deg(root.cur.temperature_2m) : "--°"
                                font.family: root.fontFamily
                                font.bold: true
                                font.features: { "tnum": 1 }
                                font.pixelSize: full.u * (full.tier === "tiny" ? 2.6 : 3.2)
                                color: root.storm ? root.critical : root.primary
                            }
                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: full.u * 0.55
                                text: root.fahrenheit ? "F" : "C"
                                font.family: root.fontFamily
                                font.bold: true
                                font.pixelSize: full.textSize(0.95)
                                color: root.accent
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.cur ? (root.storm ? "!! " : "") + root.condition(root.cur.weather_code) : ""
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.bold: true
                            font.letterSpacing: full.u * 0.05
                            font.pixelSize: full.textSize(0.8)
                            color: root.storm ? root.critical : root.accent
                            opacity: root.storm && root.blink ? 0.35 : 1
                        }
                    }

                    ColumnLayout {
                        visible: full.tier !== "tiny"
                        Layout.alignment: Qt.AlignVCenter
                        spacing: full.u * 0.2
                        Repeater {
                            model: root.wx ? [["HI", root.wx.daily.temperature_2m_max[0]],
                                              ["LO", root.wx.daily.temperature_2m_min[0]]] : []
                            RowLayout {
                                required property var modelData
                                Layout.alignment: Qt.AlignRight
                                spacing: full.u * 0.35
                                Text {
                                    text: modelData[0]
                                    font.family: root.fontFamily
                                    font.pixelSize: full.textSize(0.7)
                                    color: root.withAlpha(root.primary, 0.75)
                                }
                                Text {
                                    text: root.deg(modelData[1])
                                    font.family: root.fontFamily
                                    font.bold: true
                                    font.features: { "tnum": 1 }
                                    font.pixelSize: full.textSize(1.0)
                                    color: root.primary
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: readoutsComp
                GridLayout {
                    columns: full.tier === "wide" ? 1 : 2
                    columnSpacing: full.u * 0.8
                    rowSpacing: full.u * 0.15

                    Readout {
                        Layout.fillWidth: true; Layout.preferredWidth: full.tier === "wide" ? -1 : 1
                        label: "FEELS"; value: root.cur ? root.deg(root.cur.apparent_temperature) : "--"
                        primary: root.primary; fontFamily: root.fontFamily; pixelSize: full.textSize(0.7)
                    }
                    Readout {
                        Layout.fillWidth: true; Layout.preferredWidth: full.tier === "wide" ? -1 : 1
                        label: "HUMID"; value: root.cur ? Math.round(root.cur.relative_humidity_2m) + "%" : "--"
                        primary: root.primary; fontFamily: root.fontFamily; pixelSize: full.textSize(0.7)
                    }
                    Readout {
                        Layout.fillWidth: true; Layout.preferredWidth: full.tier === "wide" ? -1 : 1
                        label: "WIND"
                        value: root.cur ? Math.round(root.cur.wind_speed_10m) + " " + root.windUnits[root.windUnit].label
                                          + " " + root.compass(root.cur.wind_direction_10m) : "--"
                        primary: root.primary; fontFamily: root.fontFamily; pixelSize: full.textSize(0.7)
                    }
                    Readout {
                        Layout.fillWidth: true; Layout.preferredWidth: full.tier === "wide" ? -1 : 1
                        label: "PRESS"; value: root.cur ? Math.round(root.cur.surface_pressure) + " HPA" : "--"
                        primary: root.primary; fontFamily: root.fontFamily; pixelSize: full.textSize(0.7)
                    }
                    Readout {
                        Layout.fillWidth: true; Layout.preferredWidth: full.tier === "wide" ? -1 : 1
                        label: "SUN"
                        value: root.wx ? root.clock(root.wx.daily.sunrise[0]) + "–" + root.clock(root.wx.daily.sunset[0]) : "--"
                        primary: root.primary; fontFamily: root.fontFamily; pixelSize: full.textSize(0.7)
                    }
                }
            }

            Component {
                id: hourlyComp
                ColumnLayout {
                    spacing: full.u * 0.2

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "T+24H // TEMP"
                            font.family: root.fontFamily
                            font.pixelSize: full.textSize(0.7)
                            color: root.withAlpha(root.primary, 0.85)
                        }
                        Text {
                            text: "PRECIP %"
                            font.family: root.fontFamily
                            font.pixelSize: full.textSize(0.7)
                            color: root.withAlpha(root.accent, 0.85)
                        }
                    }

                    Canvas {
                        id: graph
                        Layout.fillWidth: true
                        Layout.fillHeight: full.tier === "wide"
                        Layout.preferredHeight: full.tier === "wide" ? -1 : full.u * 4.2
                        Layout.minimumHeight: full.u * 3

                        readonly property var points: root.hours
                        onPointsChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Connections {
                            target: root
                            function onPrimaryChanged() { graph.requestPaint(); }
                            function onAccentChanged() { graph.requestPaint(); }
                            function onFontFamilyChanged() { graph.requestPaint(); }
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const pts = points;
                            if (!pts || pts.length < 2)
                                return;

                            const fontPx = Math.round(full.textSize(0.66));
                            ctx.font = fontPx + "px \"" + root.fontFamily + "\"";
                            const labelH = fontPx * 1.5;            // hour labels along the bottom
                            const plotTop = fontPx * 1.4;           // room for the max-temp label
                            const plotH = height - labelH - plotTop;
                            const w = width;
                            const step = w / (pts.length - 1);
                            const barW = Math.max(1, step * 0.55);

                            for (let i = 0; i < pts.length; i++) {
                                const bh = pts[i].precip / 100 * plotH;
                                if (bh <= 0)
                                    continue;
                                ctx.fillStyle = root.css(root.accent, 0.35);
                                ctx.fillRect(i * step - barW / 2, plotTop + plotH - bh, barW, bh);
                            }

                            // temperature line, scaled to this day's range
                            let lo = Infinity, hi = -Infinity, loI = 0, hiI = 0;
                            pts.forEach((p, i) => {
                                if (p.temp < lo) { lo = p.temp; loI = i; }
                                if (p.temp > hi) { hi = p.temp; hiI = i; }
                            });
                            const span = Math.max(hi - lo, 4);      // keep small swings from looking dramatic
                            const mid = (hi + lo) / 2;
                            // line stays between 15% and 70% of the plot, leaving room
                            // under it for the low-temp label above the hour labels
                            const yOf = t => plotTop + plotH * (0.7 - 0.55 * ((t - (mid - span / 2)) / span));

                            ctx.beginPath();
                            pts.forEach((p, i) => { const x = i * step, y = yOf(p.temp); if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y); });
                            ctx.strokeStyle = root.css(root.primary, 0.95);
                            ctx.lineWidth = Math.max(1, full.u * 0.12);
                            ctx.stroke();

                            ctx.fillStyle = root.css(root.primary, 1);
                            [[hiI, hi, -fontPx * 0.5], [loI, lo, fontPx * 1.2]].forEach(([i, t, dy]) => {
                                const x = i * step, y = yOf(t);
                                ctx.fillRect(x - 2, y - 2, 4, 4);
                                const label = Math.round(t) + "°";
                                const tw = ctx.measureText(label).width;
                                ctx.fillText(label, Math.min(Math.max(0, x - tw / 2), w - tw), y + dy);
                            });

                            // baseline + hour ticks: NOW, +6H, +12H, +18H, +24H
                            const baseY = plotTop + plotH + 0.5;
                            ctx.fillStyle = root.css(root.primary, 0.25);
                            ctx.fillRect(0, baseY, w, 1);
                            ctx.fillStyle = root.css(root.primary, 0.8);
                            // label every 6 h, or every 12 h when the graph is too narrow
                            const labelEvery = 6 * step < ctx.measureText("+18H").width * 2 ? 12 : 6;
                            for (let i = 0; i < pts.length; i += 6) {
                                ctx.fillRect(i * step, baseY - 3, 1, 3);
                                if (i % labelEvery !== 0)
                                    continue;
                                const label = i === 0 ? "NOW" : "+" + i + "H";
                                const tw = ctx.measureText(label).width;
                                const x = Math.min(Math.max(0, i * step - tw / 2), w - tw);
                                ctx.fillText(label, x, baseY + fontPx * 1.2);
                            }
                        }
                    }
                }
            }

            Component {
                id: dailyComp
                RowLayout {
                    spacing: full.u * 0.3

                    Repeater {
                        model: root.days
                        ColumnLayout {
                            required property var modelData
                            required property int index
                            readonly property bool stormDay: modelData.code >= 95
                            // Equal-width columns across the full row. A layout only grows past
                            // its natural width if a child fills, so the texts below fill too.
                            // Stacked: equal shares of the row. Wide: 3.2 units each by
                            // default, stretching when the graph isn't there to take the space.
                            Layout.fillWidth: true
                            Layout.preferredWidth: full.tier === "wide" ? full.u * 3.2 : 1
                            spacing: full.u * 0.15

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                font.family: root.fontFamily
                                font.bold: index === 0
                                font.pixelSize: full.textSize(0.72)
                                color: index === 0 ? root.accent : root.withAlpha(root.primary, 0.95)
                            }
                            WxGlyph {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: full.u * 1.9
                                Layout.preferredHeight: full.u * 1.9
                                kind: root.glyphKind(modelData.code, true)
                                tint: stormDay ? root.critical : root.primary
                            }
                            // high above low, so 7 narrow columns never collide
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.deg(modelData.max)
                                font.family: root.fontFamily
                                font.bold: true
                                font.features: { "tnum": 1 }
                                font.pixelSize: full.textSize(0.8)
                                color: root.primary
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                Layout.topMargin: -full.u * 0.15
                                text: root.deg(modelData.min)
                                font.family: root.fontFamily
                                font.features: { "tnum": 1 }
                                font.pixelSize: full.textSize(0.72)
                                color: root.withAlpha(root.primary, 0.85)
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.precip + "%"
                                font.family: root.fontFamily
                                font.features: { "tnum": 1 }
                                font.pixelSize: full.textSize(0.66)
                                color: modelData.precip > 0 ? root.accent : root.withAlpha(root.primary, 0.6)
                            }
                        }
                    }
                }
            }

            // ================= stacked layout (tiny / full tiers) =================
            ColumnLayout {
                id: stacked
                visible: full.tier !== "wide"
                anchors.fill: parent
                anchors.margins: full.pad
                spacing: full.u * 0.6

                // which sections are shown (from the size planner)
                readonly property var fit: full.tier === "full" && root.wx ? full.stackPlan.keep
                                           : { daily: false, details: false, hourly: false }

                Loader {
                    id: sHeader
                    Layout.fillWidth: true
                    active: full.tier !== "tiny" && root.headerEnabled
                    visible: active
                    sourceComponent: headerComp
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: !root.wx
                    visible: active
                    sourceComponent: messageComp
                }
                Loader {
                    id: sCurrent
                    Layout.fillWidth: true
                    // tiny: take all the height so the row is centered vertically
                    Layout.fillHeight: full.tier === "tiny"
                    active: !!root.wx
                    visible: active
                    sourceComponent: currentComp
                }
                Loader {
                    id: sReadouts
                    Layout.fillWidth: true
                    active: full.tier === "full" && !!root.wx && root.showDetails
                    visible: active && stacked.fit.details
                    sourceComponent: readoutsComp
                }
                Loader {
                    id: sHourly
                    Layout.fillWidth: true
                    active: full.tier === "full" && !!root.wx && root.showHourly
                    visible: active && stacked.fit.hourly
                    sourceComponent: hourlyComp
                }
                Loader {
                    id: sDaily
                    Layout.fillWidth: true
                    active: full.tier === "full" && !!root.wx && root.showDaily
                    visible: active && stacked.fit.daily
                    sourceComponent: dailyComp
                }

                // Absorb extra height so rows stay packed at the top
                Item { Layout.fillHeight: true; visible: full.tier !== "tiny" }
            }

            // ================= wide layout: sections side by side =================
            ColumnLayout {
                id: wide
                visible: full.tier === "wide"
                anchors.fill: parent
                anchors.margins: full.pad
                spacing: full.u * 0.6

                Loader {
                    Layout.fillWidth: true
                    active: full.tier === "wide" && root.headerEnabled
                    visible: active
                    sourceComponent: headerComp
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: full.tier === "wide" && !root.wx
                    visible: active
                    sourceComponent: messageComp
                }

                RowLayout {
                    id: wideRow
                    visible: !!root.wx
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: full.u * 1.0

                    // which sections are shown (from the size planner)
                    readonly property var fit: full.tier === "wide" && root.wx ? full.widePlan.keep
                                               : { daily: false, details: false, hourly: false }

                    Loader {
                        id: wCurrent
                        Layout.alignment: Qt.AlignVCenter
                        active: full.tier === "wide" && !!root.wx
                        sourceComponent: currentComp
                    }

                    Rectangle {
                        visible: wReadouts.visible
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: root.withAlpha(root.primary, 0.25)
                    }
                    Loader {
                        id: wReadouts
                        Layout.alignment: Qt.AlignVCenter
                        active: full.tier === "wide" && !!root.wx && root.showDetails
                        visible: active && wideRow.fit.details
                        sourceComponent: readoutsComp
                    }

                    Rectangle {
                        visible: wHourly.visible
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: root.withAlpha(root.primary, 0.25)
                    }
                    Loader {
                        id: wHourly
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        active: full.tier === "wide" && !!root.wx && root.showHourly
                        visible: active && wideRow.fit.hourly
                        sourceComponent: hourlyComp
                    }

                    Rectangle {
                        visible: wDaily.visible
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: root.withAlpha(root.primary, 0.25)
                    }
                    Loader {
                        id: wDaily
                        Layout.alignment: Qt.AlignVCenter
                        // take the leftover width when there's no graph
                        Layout.fillWidth: !wHourly.visible
                        active: full.tier === "wide" && !!root.wx && root.showDaily
                        visible: active && wideRow.fit.daily
                        sourceComponent: dailyComp
                    }

                    // Neither the graph nor the forecast: keep the sections packed to the left
                    Item { Layout.fillWidth: true; visible: !wHourly.visible && !wDaily.visible }
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
