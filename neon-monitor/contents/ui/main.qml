import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---------- configuration ----------
    readonly property bool showCpu: Plasmoid.configuration.showCpu
    readonly property bool showCpuGraph: Plasmoid.configuration.showCpuGraph
    // History graphs are only drawn (and sampled) when their metric is shown too
    readonly property bool cpuGraphOn: showCpu && showCpuGraph
    readonly property bool cpuTempGraphOn: showTemp && Plasmoid.configuration.showCpuTempGraph
    readonly property bool gpuTempGraphOn: showGpuTemp && Plasmoid.configuration.showGpuTempGraph
    readonly property bool gpuPowerGraphOn: showGpuPower && Plasmoid.configuration.showGpuPowerGraph
    readonly property bool gpuClockGraphOn: showGpuClock && Plasmoid.configuration.showGpuClockGraph
    readonly property bool showGpuUsage: Plasmoid.configuration.showGpuUsage
    readonly property bool gpuUsageGraphOn: showGpuUsage && Plasmoid.configuration.showGpuUsageGraph
    readonly property bool showNetDown: Plasmoid.configuration.showNetDown
    readonly property bool showNetUp: Plasmoid.configuration.showNetUp
    readonly property bool netDownGraphOn: showNetDown && Plasmoid.configuration.showNetGraph
    readonly property bool netUpGraphOn: showNetUp && Plasmoid.configuration.showNetGraph
    readonly property bool netBits: Plasmoid.configuration.netUnit === 1
    readonly property bool showSwap: Plasmoid.configuration.showSwap
    readonly property bool showDiskRead: Plasmoid.configuration.showDiskRead
    readonly property bool showDiskWrite: Plasmoid.configuration.showDiskWrite
    readonly property bool diskReadGraphOn: showDiskRead && Plasmoid.configuration.showDiskIoGraph
    readonly property bool diskWriteGraphOn: showDiskWrite && Plasmoid.configuration.showDiskIoGraph
    readonly property bool showRam: Plasmoid.configuration.showRam
    readonly property bool showTemp: Plasmoid.configuration.showTemp
    readonly property bool showGpuTemp: Plasmoid.configuration.showGpuTemp
    readonly property bool showGpuPower: Plasmoid.configuration.showGpuPower
    readonly property bool showGpuClock: Plasmoid.configuration.showGpuClock
    readonly property bool showGpuVram: Plasmoid.configuration.showGpuVram
    readonly property bool anyGpu: showGpuUsage || showGpuTemp || showGpuPower || showGpuClock || showGpuVram
    readonly property int gpuPowerSetting: Plasmoid.configuration.gpuPowerScale   // W, 0 = auto
    readonly property string gpuSensorBase: "gpu/gpu" + Plasmoid.configuration.gpuIndex
    readonly property bool showDisk: Plasmoid.configuration.showDisk
    readonly property int updateInterval: Plasmoid.configuration.updateInterval
    readonly property var mounts: String(Plasmoid.configuration.mountPoints || "/")
                                      .split(",").map(s => s.trim()).filter(s => s.length > 0)
    readonly property string tempSensorId: Plasmoid.configuration.tempSource === 1
                                           ? "cpu/all/maximumTemperature"
                                           : "cpu/all/averageTemperature"

    readonly property bool holo: Plasmoid.configuration.style === 1
    readonly property int barStyle: Plasmoid.configuration.barStyle
    readonly property bool borderEnabled: Plasmoid.configuration.showBorder
    readonly property bool headerEnabled: Plasmoid.configuration.showHeader
    readonly property bool glowEnabled: Plasmoid.configuration.glow
    readonly property bool scanlinesEnabled: Plasmoid.configuration.scanlines
    readonly property bool sweepEnabled: Plasmoid.configuration.scanSweep
    readonly property color primary: Plasmoid.configuration.primaryColor
    readonly property color accent: Plasmoid.configuration.accentColor
    // Warning state color: the accent color unless the user chose a separate one
    readonly property color warning: Plasmoid.configuration.warningSameAsAccent
                                     ? accent : Plasmoid.configuration.warningColor
    readonly property color critical: Plasmoid.configuration.criticalColor
    readonly property real backgroundAlpha: Plasmoid.configuration.backgroundOpacity / 100
    readonly property string fontFamily: Plasmoid.configuration.fontFamily || "monospace"

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                                 || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The full view is on screen: always on the desktop, only while the popup is open in a panel
    readonly property bool fullShown: !inPanel || expanded

    // ---------- thresholds ----------
    // warning = accent color, critical = critical color + blinking
    readonly property real cpuWarn: Plasmoid.configuration.cpuWarn
    readonly property real cpuCrit: Plasmoid.configuration.cpuCrit
    readonly property real ramWarn: Plasmoid.configuration.ramWarn
    readonly property real ramCrit: Plasmoid.configuration.ramCrit
    readonly property real diskWarn: Plasmoid.configuration.diskWarn
    readonly property real diskCrit: Plasmoid.configuration.diskCrit
    readonly property real cpuTempWarn: Plasmoid.configuration.cpuTempWarn   // °C
    readonly property real cpuTempCrit: Plasmoid.configuration.cpuTempCrit
    readonly property real gpuTempWarn: Plasmoid.configuration.gpuTempWarn   // °C
    readonly property real gpuTempCrit: Plasmoid.configuration.gpuTempCrit
    readonly property real vramWarn: Plasmoid.configuration.vramWarn
    readonly property real vramCrit: Plasmoid.configuration.vramCrit
    readonly property real tempMin: 20                                       // °C, bar scale start

    // ---------- sensors (ksystemstats) ----------
    property QtObject sensors: null
    property bool sensorModuleMissing: false
    Component.onCompleted: {
        const c = Qt.createComponent("SensorSet.qml");
        if (c.status === Component.Ready) {
            sensors = c.createObject(root, { host: root });
        } else {
            sensorModuleMissing = true;
            console.warn("Neon Monitor: system sensors unavailable:", c.errorString());
        }
    }

    property bool sensorWaitOver: false
    Timer {
        interval: 10000
        running: true
        onTriggered: root.sensorWaitOver = true
    }
    readonly property string sensorProblem: sensorModuleMissing ? "NO SENSOR MODULE"
                                          : sensorWaitOver && isNaN(num(sensors?.probeSensor)) ? "NO SENSOR SERVICE"
                                          : ""

    // A sensor ID that doesn't exist stays "Loading" forever instead of reporting an
    // error, so give up after a few seconds without data.
    // Some GPU drivers (e.g. NVIDIA's) also report 0 for everything before their
    // first real sample, so a 0 only counts as a reading once that time has passed:
    // integrated and some AMD GPUs really do read 0 W or 0 % VRAM.
    property bool gpuSettled: false
    property bool gpuTimedOut: false
    Timer {
        id: gpuTimeout
        interval: 5000
        running: root.anyGpu
        onTriggered: {
            root.gpuSettled = true;
            root.gpuTimedOut = !root.gpuHasData;
        }
    }
    onGpuSensorBaseChanged: {
        gpuSettled = false;
        gpuTimedOut = false;
        gpuPowerPeak = 0;
        gpuClockPeak = 0;
        gpuTimeout.restart();
    }

    // Same for the CPU temperature: some machines (virtual machines, some CPUs)
    // have no temperature sensor at all.
    property bool cpuTempTimedOut: false
    Timer {
        id: cpuTempTimeout
        interval: 5000
        running: root.showTemp
        onTriggered: root.cpuTempTimedOut = isNaN(root.temp)
    }
    onTempSensorIdChanged: { cpuTempTimedOut = false; cpuTempTimeout.restart(); }

    readonly property real cpu: num(sensors?.cpuSensor)
    readonly property real ram: num(sensors?.ramSensor)
    readonly property real temp: tempNum(sensors?.tempSensor)
    readonly property real gpuTemp: tempNum(sensors?.gpuTempSensor)
    readonly property real gpuPower: gpuNum(sensors?.gpuPowerSensor)        // W
    readonly property real gpuClock: gpuNum(sensors?.gpuClockSensor)        // MHz
    readonly property real gpuClockMax: sensors?.gpuClockSensor?.maximum > 0 ? sensors?.gpuClockSensor?.maximum : NaN

    // Highest readings seen, for scales the hardware doesn't report
    property real gpuPowerPeak: 0
    property real gpuClockPeak: 0
    onGpuPowerChanged: if (gpuPower > gpuPowerPeak) gpuPowerPeak = gpuPower
    onGpuClockChanged: if (gpuClock > gpuClockPeak) gpuClockPeak = gpuClock

    // Power bar scale: the configured wattage, or (auto) the peak so far rounded up to 25 W
    readonly property bool gpuPowerAuto: gpuPowerSetting <= 0
    readonly property real gpuPowerScale: gpuPowerAuto ? Math.max(25, Math.ceil(gpuPowerPeak / 25) * 25)
                                                       : gpuPowerSetting
    // Clock bar scale: the card's reported max clock, else the peak so far rounded up to 100 MHz
    readonly property real gpuClockScale: !isNaN(gpuClockMax) ? gpuClockMax
                                          : Math.max(100, Math.ceil(gpuClockPeak / 100) * 100)
    readonly property real gpuVram: gpuNum(sensors?.gpuVramSensor)          // %
    readonly property real gpuUsage: gpuNum(sensors?.gpuUsageSensor)        // %
    readonly property bool gpuHasData: !isNaN(gpuTemp) || !isNaN(gpuPower) || !isNaN(gpuClock) || !isNaN(gpuVram)
                                       || !isNaN(gpuUsage)

    // Network speeds in bytes per second. 0 is a normal reading here (idle).
    readonly property real netDown: num(sensors?.netDownSensor)
    readonly property real netUp: num(sensors?.netUpSensor)
    // Bars scale to the fastest speed seen, rounded up to 1/2/5 x 10^n, and at
    // least 1 MB/s so an idle connection doesn't look busy.
    property real netDownPeak: 0
    property real netUpPeak: 0
    onNetDownChanged: if (netDown > netDownPeak) netDownPeak = netDown
    onNetUpChanged: if (netUp > netUpPeak) netUpPeak = netUp
    readonly property real netDownScale: niceCeil(Math.max(1e6, netDownPeak))
    readonly property real netUpScale: niceCeil(Math.max(1e6, netUpPeak))

    // Swap: no swap configured reads as total 0
    readonly property real swapTotal: num(sensors?.swapTotalSensor)
    readonly property bool noSwap: swapTotal === 0
    readonly property real swap: noSwap ? NaN : num(sensors?.swapSensor)

    // Disk activity, bytes per second; idle is a normal 0. Scaled like the network.
    readonly property real diskRead: num(sensors?.diskReadSensor)
    readonly property real diskWrite: num(sensors?.diskWriteSensor)
    property real diskReadPeak: 0
    property real diskWritePeak: 0
    onDiskReadChanged: if (diskRead > diskReadPeak) diskReadPeak = diskRead
    onDiskWriteChanged: if (diskWrite > diskWritePeak) diskWritePeak = diskWrite
    readonly property real diskReadScale: niceCeil(Math.max(1e6, diskReadPeak))
    readonly property real diskWriteScale: niceCeil(Math.max(1e6, diskWritePeak))
    // Text for a GPU row with no value yet: still waiting, or the sensor doesn't exist
    readonly property string gpuNoData: gpuTimedOut ? "NO GPU SENSOR" : "SCANNING…"
    readonly property string gpuName: String(sensors?.gpuNameSensor?.value || "")
                                          .replace(/^(NVIDIA|AMD|Intel)\s+/i, "")
                                          .replace(/^(GeForce|Radeon)\s+/i, "")
                                          .toUpperCase()

    // ---------- storage (df) ----------
    // ksystemstats only reports some filesystems (e.g. not btrfs on LUKS), so read
    // usage with df instead. Disk space changes slowly, so poll every 30 s.
    property var diskData: ({})   // mount path -> { size, used, target } in bytes

    function dfCommand(path) {
        return "df -B1 --output=size,used,target -- '" + path.replace(/'/g, "'\\''") + "'";
    }

    P5Support.DataSource {
        id: dfSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const path = root.mounts.find(m => root.dfCommand(m) === sourceName);
            disconnectSource(sourceName);
            if (path === undefined)
                return;
            const lines = String(data.stdout || "").trim().split("\n");
            const m = lines.length > 1 ? lines[lines.length - 1].match(/^\s*(\d+)\s+(\d+)\s+(.+)$/) : null;
            const next = Object.assign({}, root.diskData);
            next[path] = m ? { size: Number(m[1]), used: Number(m[2]), target: m[3] } : null;
            root.diskData = next;
        }
    }

    function refreshDisks() {
        for (const m of mounts)
            dfSource.connectSource(dfCommand(m));
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.showDisk
        triggeredOnStart: true
        onTriggered: root.refreshDisks()
    }
    onMountsChanged: if (showDisk) refreshDisks()

    // ---------- history (last 60 samples, one per update) ----------
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var cpuTempHistory: []
    property var gpuTempHistory: []
    property var gpuPowerHistory: []
    property var gpuClockHistory: []
    property var gpuUsageHistory: []
    property var netDownHistory: []
    property var netUpHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []

    // Returns a new array (so bindings see the change); skips missing readings.
    function pushSample(history, value) {
        if (isNaN(value))
            return history;
        const h = history.slice(-(historyLength - 1));
        h.push(value);
        return h;
    }

    // One tick per update interval: record history samples, then rebuild the metric
    // table the views read from. (Sensors report one at a time; rebuilding on each
    // report would redo the whole table ~10x a second for no visible difference.)
    Timer {
        interval: root.updateInterval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.cpuGraphOn) root.cpuHistory = root.pushSample(root.cpuHistory, root.cpu);
            if (root.cpuTempGraphOn) root.cpuTempHistory = root.pushSample(root.cpuTempHistory, root.temp);
            if (root.gpuTempGraphOn) root.gpuTempHistory = root.pushSample(root.gpuTempHistory, root.gpuTemp);
            if (root.gpuPowerGraphOn) root.gpuPowerHistory = root.pushSample(root.gpuPowerHistory, root.gpuPower);
            if (root.gpuClockGraphOn) root.gpuClockHistory = root.pushSample(root.gpuClockHistory, root.gpuClock);
            if (root.gpuUsageGraphOn) root.gpuUsageHistory = root.pushSample(root.gpuUsageHistory, root.gpuUsage);
            if (root.netDownGraphOn) root.netDownHistory = root.pushSample(root.netDownHistory, root.netDown);
            if (root.netUpGraphOn) root.netUpHistory = root.pushSample(root.netUpHistory, root.netUp);
            if (root.diskReadGraphOn) root.diskReadHistory = root.pushSample(root.diskReadHistory, root.diskRead);
            if (root.diskWriteGraphOn) root.diskWriteHistory = root.pushSample(root.diskWriteHistory, root.diskWrite);
            root.metricData = root.buildMetricData();
        }
    }

    // Shared blink phase for critical values; only needed while the full view is shown
    property bool blink: false
    Timer {
        interval: 500
        repeat: true
        running: root.fullShown
        onTriggered: root.blink = !root.blink
    }

    // ---------- helpers ----------
    // GPU power / clock / VRAM: 0 is a real reading, but only once the driver has
    // had time to report its first sample (see gpuSettled).
    function gpuNum(sensor) {
        const v = num(sensor);
        return v > 0 || (v === 0 && gpuSettled) ? v : NaN;
    }
    // Temperatures: 0 °C (or below) from a CPU/GPU sensor means "no reading yet".
    function tempNum(sensor) {
        const v = num(sensor);
        return v > 0 ? v : NaN;
    }
    function num(sensor) {
        const v = sensor ? sensor.value : undefined;
        return (typeof v === "number" && isFinite(v)) ? v : NaN;
    }
    // Smallest 1, 2 or 5 x 10^n that's >= v
    function niceCeil(v) {
        const p = Math.pow(10, Math.floor(Math.log10(v)));
        for (const m of [1, 2, 5, 10])
            if (v <= m * p)
                return m * p;
        return 10 * p;
    }
    // Network speed (bytes/s) as text: KiB/s, MiB/s... or Kbps, Mbps... (setting)
    // inBits: show as bits per second (network setting); disk speeds are always bytes
    function speed(bytesPerSec, inBits) {
        const bits = inBits === undefined ? netBits : inBits;
        if (isNaN(bytesPerSec))
            return bits ? "-- Mbps" : "-- MiB/s";
        let v = bits ? bytesPerSec * 8 : bytesPerSec;
        const base = bits ? 1000 : 1024;
        const units = bits ? ["bps", "Kbps", "Mbps", "Gbps"] : ["B/s", "KiB/s", "MiB/s", "GiB/s"];
        let i = 0;
        while (v >= base && i < units.length - 1) { v /= base; i++; }
        return v.toFixed(v >= 10 || i === 0 ? 0 : 1) + " " + units[i];
    }
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + a + ")";
    }
    function pct(v) { return isNaN(v) ? "--%" : Math.round(v) + "%"; }
    function degrees(v) { return isNaN(v) ? "--°C" : Math.round(v) + "°C"; }
    function bytes(b) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
        return b.toFixed(b >= 100 || i === 0 ? 0 : 1) + " " + units[i];
    }
    function diskLabel(path) {
        if (path === "/")
            return "DSK.ROOT";
        const parts = path.split("/").filter(s => s.length > 0);
        return "DSK." + (parts.length ? parts[parts.length - 1] : path).toUpperCase();
    }
    function tempStatus(t, tag, warnAt, critAt) {
        return isNaN(t) ? ""
             : t >= critAt ? "!! OVERHEAT"
             : t >= warnAt ? "HOT"
             : (tag ? tag + " // " : "") + "NOMINAL";
    }
    // Bar fill for a temperature. The scale ends at 100 °C, or above the critical
    // level if that's set higher, so the bar never fills before reaching it.
    function tempFraction(t, critAt) {
        return (t - tempMin) / (Math.max(100, critAt + 10) - tempMin);
    }
    function diskPercent(d) { return d && d.size > 0 ? d.used / d.size * 100 : NaN; }

    // ---------- metric list (shared by all views) ----------
    // Keys of the metrics to show, in display order. Only changes with the settings (or sensor state),
    // so the views don't rebuild on every sensor update.
    readonly property var metricKeys: {
        const k = [];
        if (showCpu) k.push("cpu");
        if (showRam) k.push("ram");
        if (showSwap) k.push("swap");
        if (showTemp) k.push("cpuTemp");
        if (showGpuUsage) k.push("gpuUsage");
        if (showGpuTemp) k.push("gpuTemp");
        if (showGpuPower) k.push("gpuPower");
        if (showGpuClock) k.push("gpuClock");
        if (showGpuVram) k.push("gpuVram");
        if (showNetDown) k.push("netDown");
        if (showNetUp) k.push("netUp");
        if (showDiskRead) k.push("diskRead");
        if (showDiskWrite) k.push("diskWrite");
        // One row instead of a column of "--"
        if (sensorProblem && k.length) k.splice(0, k.length, "offline");
        if (showDisk)
            for (const m of mounts) k.push("disk:" + m);
        return k;
    }
    // Whether a metric has its history graph turned on (settings only, not live data)
    function hasGraph(key) {
        return key === "cpu" ? cpuGraphOn
             : key === "cpuTemp" ? cpuTempGraphOn
             : key === "gpuTemp" ? gpuTempGraphOn
             : key === "gpuPower" ? gpuPowerGraphOn
             : key === "gpuClock" ? gpuClockGraphOn
             : key === "gpuUsage" ? gpuUsageGraphOn
             : key === "netDown" ? netDownGraphOn
             : key === "netUp" ? netUpGraphOn
             : key === "diskRead" ? diskReadGraphOn
             : key === "diskWrite" ? diskWriteGraphOn
             : false;
    }
    function diskShort(path) {
        if (path === "/")
            return "ROOT";
        const parts = path.split("/").filter(s => s.length > 0);
        return (parts.length ? parts[parts.length - 1] : path).toUpperCase();
    }

    // Live values per metric: label (full view), short label (dense/tiny views),
    // value, detail text, bar fill (0..1), alert state and history graph.
    property var metricData: ({})
    onMetricKeysChanged: metricData = buildMetricData()
    readonly property var emptyMetric: ({ label: "", short: "", value: "", detail: "", fraction: NaN,
                                          warn: false, crit: false, graph: null })
    readonly property var noSamples: []
    function buildMetricData() {
        const graph = (on, samples, min, max, warnAt, critAt) =>
            on ? { samples: samples, min: min, max: max, warnAt: warnAt, critAt: critAt } : null;
        const d = {};
        d.cpu = {
            label: "CPU.USAGE", short: "CPU", value: pct(cpu),
            detail: sensors?.cpuFreqSensor?.formattedValue || "",
            fraction: cpu / 100, warn: cpu >= cpuWarn, crit: cpu >= cpuCrit,
            graph: graph(cpuGraphOn, cpuHistory, 0, 100, cpuWarn, cpuCrit)
        };
        d.ram = {
            label: "MEM.RAM", short: "RAM", value: pct(ram),
            detail: (sensors?.ramUsedSensor?.formattedValue && sensors?.ramTotalSensor?.formattedValue)
                    ? sensors?.ramUsedSensor?.formattedValue + " / " + sensors?.ramTotalSensor?.formattedValue : "",
            fraction: ram / 100, warn: ram >= ramWarn, crit: ram >= ramCrit, graph: null
        };
        d.cpuTemp = {
            label: "CORE.TEMP", short: "C.TMP", value: degrees(temp),
            detail: isNaN(temp) ? (cpuTempTimedOut ? "NO TEMP SENSOR" : "SCANNING…")
                    : tempStatus(temp, Plasmoid.configuration.tempSource === 1 ? "MAX" : "AVG", cpuTempWarn, cpuTempCrit),
            fraction: tempFraction(temp, cpuTempCrit), warn: temp >= cpuTempWarn, crit: temp >= cpuTempCrit,
            graph: graph(cpuTempGraphOn, cpuTempHistory, tempMin, Math.max(100, cpuTempCrit + 10), cpuTempWarn, cpuTempCrit)
        };
        d.gpuUsage = {
            label: "GPU.USAGE", short: "G.USE", value: pct(gpuUsage),
            detail: isNaN(gpuUsage) ? gpuNoData : gpuName,
            fraction: gpuUsage / 100, warn: false, crit: false,
            graph: graph(gpuUsageGraphOn, gpuUsageHistory, 0, 100, NaN, NaN)
        };
        d.netDown = {
            label: "NET.DOWN", short: "N.DWN", value: speed(netDown),
            detail: isNaN(num(sensors?.netTotalDownSensor)) ? "" : "TOTAL " + bytes(num(sensors?.netTotalDownSensor)),
            fraction: netDown / netDownScale, warn: false, crit: false,
            graph: graph(netDownGraphOn, netDownHistory, 0, netDownScale, NaN, NaN)
        };
        d.netUp = {
            label: "NET.UP", short: "N.UP", value: speed(netUp),
            detail: isNaN(num(sensors?.netTotalUpSensor)) ? "" : "TOTAL " + bytes(num(sensors?.netTotalUpSensor)),
            fraction: netUp / netUpScale, warn: false, crit: false,
            graph: graph(netUpGraphOn, netUpHistory, 0, netUpScale, NaN, NaN)
        };
        d.swap = {
            label: "MEM.SWAP", short: "SWAP", value: pct(swap),
            detail: noSwap ? "NO SWAP"
                    : (sensors?.swapUsedSensor?.formattedValue && sensors?.swapTotalSensor?.formattedValue)
                      ? sensors?.swapUsedSensor?.formattedValue + " / " + sensors?.swapTotalSensor?.formattedValue : "",
            fraction: swap / 100, warn: false, crit: false, graph: null
        };
        d.diskRead = {
            label: "DSK.READ", short: "D.RD", value: speed(diskRead, false),
            detail: "PEAK " + speed(diskReadPeak, false),
            fraction: diskRead / diskReadScale, warn: false, crit: false,
            graph: graph(diskReadGraphOn, diskReadHistory, 0, diskReadScale, NaN, NaN)
        };
        d.diskWrite = {
            label: "DSK.WRITE", short: "D.WR", value: speed(diskWrite, false),
            detail: "PEAK " + speed(diskWritePeak, false),
            fraction: diskWrite / diskWriteScale, warn: false, crit: false,
            graph: graph(diskWriteGraphOn, diskWriteHistory, 0, diskWriteScale, NaN, NaN)
        };
        d.gpuTemp = {
            label: "GPU.TEMP", short: "G.TMP", value: degrees(gpuTemp),
            detail: isNaN(gpuTemp) ? gpuNoData : tempStatus(gpuTemp, gpuName, gpuTempWarn, gpuTempCrit),
            fraction: tempFraction(gpuTemp, gpuTempCrit), warn: gpuTemp >= gpuTempWarn, crit: gpuTemp >= gpuTempCrit,
            graph: graph(gpuTempGraphOn, gpuTempHistory, tempMin, Math.max(100, gpuTempCrit + 10), gpuTempWarn, gpuTempCrit)
        };
        d.gpuPower = {
            label: "GPU.POWER", short: "G.PWR",
            value: isNaN(gpuPower) ? "-- W" : Math.round(gpuPower) + " W",
            detail: isNaN(gpuPower) ? gpuNoData
                    : gpuPowerAuto ? "PEAK " + Math.round(gpuPowerPeak) + " W"
                    : Math.round(gpuPower / gpuPowerScale * 100) + "% OF " + gpuPowerScale + " W",
            fraction: gpuPower / gpuPowerScale, warn: false, crit: false,
            graph: graph(gpuPowerGraphOn, gpuPowerHistory, 0, gpuPowerScale, NaN, NaN)
        };
        d.gpuClock = {
            label: "GPU.CLOCK", short: "G.CLK",
            value: isNaN(gpuClock) ? "-- MHz" : Math.round(gpuClock) + " MHz",
            detail: isNaN(gpuClock) ? gpuNoData
                    : isNaN(gpuClockMax) ? "PEAK " + Math.round(gpuClockPeak) + " MHz"
                    : "MAX " + Math.round(gpuClockMax) + " MHz",
            fraction: gpuClock / gpuClockScale, warn: false, crit: false,
            graph: graph(gpuClockGraphOn, gpuClockHistory, 0, gpuClockScale, NaN, NaN)
        };
        d.gpuVram = {
            label: "GPU.VRAM", short: "VRAM", value: pct(gpuVram),
            detail: isNaN(gpuVram) ? gpuNoData
                    : (sensors?.gpuVramUsedSensor?.formattedValue && sensors?.gpuVramTotalSensor?.formattedValue)
                      ? sensors?.gpuVramUsedSensor?.formattedValue + " / " + sensors?.gpuVramTotalSensor?.formattedValue : "",
            fraction: gpuVram / 100, warn: gpuVram >= vramWarn, crit: gpuVram >= vramCrit, graph: null
        };
        for (const m of mounts) {
            const disk = diskData[m];
            const p = diskPercent(disk);
            d["disk:" + m] = {
                label: diskLabel(m), short: diskShort(m), value: pct(p),
                detail: disk === null ? "NOT FOUND" : disk ? bytes(disk.used) + " / " + bytes(disk.size) : "",
                fraction: p / 100, warn: p >= diskWarn, crit: p >= diskCrit, graph: null
            };
        }
        d.offline = {
            label: "SYS.SENSORS", short: "SENSORS", value: "OFF", detail: sensorProblem,
            fraction: NaN, warn: true, crit: false, graph: null
        };
        return d;
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    toolTipMainText: i18n("System monitor")
    // built from the once-per-tick metric table, like the views
    toolTipSubText: (sensorProblem ? i18n("System sensors unavailable: is ksystemstats installed?") + "\n" : "")
                    + metricKeys.map(k => {
        const m = metricData[k];
        return m ? m.short + " " + m.value : "";
    }).filter(t => t).join("  ·  ")

    // Note: inline components can't see ids from this file (like `root`),
    // so anything that depends on root is set where they're used.

    // One metric: label, detail, value, and a segmented bar.
    component MetricRow: ColumnLayout {
        id: row
        property string label
        property string detailText
        property string valueText
        property real fraction: NaN      // 0..1, NaN = no data yet
        property bool warn: false
        property bool crit: false
        property bool blink: false
        property real u: 8
        property real minText: 8
        property color primary: "cyan"
        property color warning: "magenta"
        property color critical: "red"
        property int barStyle: 0
        property string fontFamily: "monospace"

        readonly property color tone: crit ? critical : warn ? warning : primary

        Layout.fillWidth: true
        spacing: u * 0.3

        RowLayout {
            Layout.fillWidth: true
            spacing: row.u * 0.5

            Rectangle {
                Layout.preferredWidth: Math.max(2, row.u * 0.22)
                Layout.preferredHeight: row.u * 0.95
                color: row.tone
                opacity: row.crit && row.blink ? 0.2 : 1
            }
            Text {
                id: labelText
                text: row.label
                font.family: row.fontFamily
                font.bold: true
                font.pixelSize: Math.max(row.minText, row.u * 0.85)
                font.letterSpacing: row.u * 0.06
                color: row.primary
                opacity: 0.85
            }
            Text {
                // Take only the space left between label and value, and shrink the
                // font to fit it. Elide only if it still doesn't fit at the minimum size.
                // With shrink-to-fit, Text can report a taller implicit height than it
                // draws, which would make the whole row taller; cap it at the label line.
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.maximumHeight: labelText.implicitHeight
                text: row.detailText
                font.family: row.fontFamily
                font.features: { "tnum": 1 }
                font.pixelSize: Math.max(row.minText, row.u * 0.78)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.max(6, Math.round(font.pixelSize * 0.55))
                color: Qt.rgba(row.primary.r, row.primary.g, row.primary.b, 0.8)
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideLeft
            }
            Text {
                text: row.valueText
                font.family: row.fontFamily
                font.bold: true
                font.features: { "tnum": 1 }
                font.pixelSize: Math.max(row.minText, row.u * 1.35)
                color: row.tone
                opacity: row.crit && row.blink ? 0.35 : 1
                horizontalAlignment: Text.AlignRight
                // Fixed width so the bar layout doesn't jump as digits change
                Layout.minimumWidth: row.u * 4.2
            }
        }

        SegmentBar {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(3, row.u * 0.55)
            fraction: row.fraction
            u: row.u
            tone: row.tone
            primary: row.primary
            style: row.barStyle
        }
    }

    // style: 0 segmented, 1 solid, 2 thin line, 3 gradient
    component SegmentBar: Item {
        id: bar
        property real fraction: NaN      // 0..1, NaN = no data yet
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

    // One metric on a single line (dense view): marker, short label, bar, value.
    component DenseRow: RowLayout {
        id: dense
        property string label
        property string valueText
        property real fraction: NaN
        property bool warn: false
        property bool crit: false
        property bool blink: false
        property real u: 8
        property color primary: "cyan"
        property color warning: "magenta"
        property color critical: "red"
        property int barStyle: 0
        property string fontFamily: "monospace"
        readonly property color tone: crit ? critical : warn ? warning : primary

        Layout.fillWidth: true
        spacing: u * 0.5

        Rectangle {
            Layout.preferredWidth: Math.max(2, dense.u * 0.22)
            Layout.preferredHeight: dense.u * 0.8
            color: dense.tone
            opacity: dense.crit && dense.blink ? 0.2 : 1
        }
        Text {
            Layout.preferredWidth: dense.u * 3.6
            text: dense.label
            elide: Text.ElideRight
            font.family: dense.fontFamily
            font.bold: true
            font.pixelSize: dense.u * 0.75
            color: dense.primary
            opacity: 0.85
        }
        SegmentBar {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(3, dense.u * 0.5)
            fraction: dense.fraction
            u: dense.u
            tone: dense.tone
            primary: dense.primary
            style: dense.barStyle
        }
        Text {
            Layout.preferredWidth: dense.u * 4.6
            text: dense.valueText
            horizontalAlignment: Text.AlignRight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.max(6, font.pixelSize * 0.6)
            font.family: dense.fontFamily
            font.bold: true
            font.features: { "tnum": 1 }
            font.pixelSize: dense.u * 1.05
            color: dense.tone
            opacity: dense.crit && dense.blink ? 0.35 : 1
        }
    }

    // Scrolling history graph: filled area + line, newest sample at the right.
    // Optional dashed lines mark the warning / critical levels, and the line
    // takes the warning / critical color while the latest sample is past them.
    component HistoryGraph: Canvas {
        id: hg
        property var samples: []
        property int length: 60
        property real minValue: 0
        property real maxValue: 100
        property real warnAt: NaN
        property real critAt: NaN
        property real u: 8
        property color primary: "cyan"
        property color warning: "magenta"
        property color critical: "red"

        Layout.fillWidth: true
        Layout.preferredHeight: u * 2.1
        Layout.topMargin: -u * 0.15

        onSamplesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPrimaryChanged: requestPaint()
        onWarningChanged: requestPaint()
        onCriticalChanged: requestPaint()
        onWarnAtChanged: requestPaint()
        onCritAtChanged: requestPaint()
        onMaxValueChanged: requestPaint()

        function rgba(c, a) {
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                   + Math.round(c.b * 255) + "," + a + ")";
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            const span = maxValue - minValue;
            const yOf = v => h - Math.max(0, Math.min(1, (v - minValue) / span)) * (h - 1);
            const dashed = (y, color) => {
                ctx.strokeStyle = color;
                ctx.lineWidth = 1;
                for (let x = 0; x < w; x += 6) {
                    ctx.beginPath();
                    ctx.moveTo(x, y);
                    ctx.lineTo(Math.min(w, x + 2), y);
                    ctx.stroke();
                }
            };

            for (let q = 1; q < 4; q++)
                dashed(Math.round(h * q / 4) + 0.5, rgba(primary, 0.12));
            if (!isNaN(warnAt) && warnAt > minValue && warnAt < maxValue)
                dashed(Math.round(yOf(warnAt)) + 0.5, rgba(warning, 0.45));
            if (!isNaN(critAt) && critAt > minValue && critAt < maxValue)
                dashed(Math.round(yOf(critAt)) + 0.5, rgba(critical, 0.5));

            const pts = samples;
            if (!pts || pts.length < 2)
                return;
            const last = pts[pts.length - 1];
            const tone = last >= critAt ? critical : last >= warnAt ? warning : primary;
            const step = w / (length - 1);
            const x0 = w - (pts.length - 1) * step;

            ctx.beginPath();
            ctx.moveTo(x0, h);
            for (let i = 0; i < pts.length; i++)
                ctx.lineTo(x0 + i * step, yOf(pts[i]));
            ctx.lineTo(w, h);
            ctx.closePath();
            const g = ctx.createLinearGradient(0, 0, 0, h);
            g.addColorStop(0, rgba(tone, 0.35));
            g.addColorStop(1, rgba(tone, 0.0));
            ctx.fillStyle = g;
            ctx.fill();

            ctx.beginPath();
            for (let i = 0; i < pts.length; i++) {
                const x = x0 + i * step, y = yOf(pts[i]);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.strokeStyle = rgba(tone, 0.9);
            ctx.lineWidth = Math.max(1, u * 0.1);
            ctx.stroke();
        }
    }

    component CompactStat: Row {
        id: stat
        property string label
        property string valueText
        property bool warn: false
        property bool crit: false
        property color primary: "cyan"
        property color accent: "magenta"
        property color warning: "magenta"
        property color critical: "red"
        property string fontFamily: "monospace"
        property real pixelSize: 12
        spacing: pixelSize * 0.3

        Text {
            text: stat.label
            font.family: stat.fontFamily
            font.pixelSize: stat.pixelSize * 0.75
            color: stat.accent
            anchors.baseline: valueLabel.baseline
        }
        Text {
            id: valueLabel
            text: stat.valueText
            font.family: stat.fontFamily
            font.bold: true
            font.features: { "tnum": 1 }
            font.pixelSize: stat.pixelSize
            color: stat.crit ? stat.critical : stat.warn ? stat.warning : stat.primary
        }
    }

    // ================= panel view =================
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real pixelSize: vertical ? width * 0.2 : height * 0.42

        Layout.minimumWidth: vertical ? 0 : grid.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? grid.implicitHeight + Kirigami.Units.smallSpacing * 2 : 0
        onClicked: root.expanded = !root.expanded

        GridLayout {
            id: grid
            anchors.centerIn: parent
            flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: compact.vertical ? -1 : 1
            columns: compact.vertical ? 1 : -1
            columnSpacing: compact.pixelSize * 0.8
            rowSpacing: compact.pixelSize * 0.2

            CompactStat {
                visible: root.sensorProblem !== "" && (root.showCpu || root.showRam || root.showTemp || root.showGpuTemp)
                label: "SENSORS"; valueText: "OFF"
                warn: true; crit: false
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
            CompactStat {
                visible: root.showCpu && !root.sensorProblem
                label: "CPU"; valueText: root.pct(root.cpu)
                warn: root.cpu >= root.cpuWarn
                crit: root.cpu >= root.cpuCrit
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
            CompactStat {
                visible: root.showRam && !root.sensorProblem
                label: "RAM"; valueText: root.pct(root.ram)
                warn: root.ram >= root.ramWarn
                crit: root.ram >= root.ramCrit
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
            CompactStat {
                visible: root.showTemp && !root.sensorProblem
                label: "TMP"; valueText: root.degrees(root.temp)
                warn: root.temp >= root.cpuTempWarn
                crit: root.temp >= root.cpuTempCrit
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
            CompactStat {
                visible: root.showGpuTemp && !root.sensorProblem
                label: "GPU"; valueText: root.degrees(root.gpuTemp)
                warn: root.gpuTemp >= root.gpuTempWarn
                crit: root.gpuTemp >= root.gpuTempCrit
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
            CompactStat {
                // Panel space is tight: show only the first mount point
                visible: root.showDisk && root.mounts.length > 0
                readonly property real p: root.diskPercent(root.diskData[root.mounts[0]])
                label: "DSK"; valueText: root.pct(p)
                warn: p >= root.diskWarn
                crit: p >= root.diskCrit
                primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                fontFamily: root.fontFamily; pixelSize: compact.pixelSize
            }
        }
    }

    // ================= desktop / popup view =================
    fullRepresentation: Item {
        id: full

        // ---- views ----
        // The widget picks how to show the metrics from its size. Metrics are never
        // dropped (they're what the user chose); only their presentation changes:
        //   graphs - full rows with history graphs
        //   full   - full rows, graphs hidden
        //   dense  - one line per metric, no detail text
        //   tiny   - values only, no header
        // Each of the first three is tried with 1-3 columns (whichever gives the
        // largest text); the first that stays readable wins. Wide widgets therefore
        // get columns, short ones get dense rows, very small ones get tiny.
        readonly property real gu: Kirigami.Units.gridUnit

        // Font line height per pixel of font size, to turn font sizes into heights
        FontMetrics {
            id: fm
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: 100
        }
        readonly property real lineF: Math.max(1, fm.height / 100)
        readonly property real charF: Math.max(0.4, fm.averageCharacterWidth / 100)

        // Heights and widths in units of u
        readonly property real chromeU: (0.4 + 0.5 + 0.9) * 2         // frame + effect padding + margins
        readonly property real gapU: 0.55                                // between rows
        readonly property real denseGapU: 0.3
        // (constants checked against measured layouts)
        readonly property real headerU: root.headerEnabled ? 0.85 * lineF + 1.15 : 0   // header, divider, gaps
        readonly property real rowU: 1.35 * lineF + 0.95                 // value line + gap + bar
        readonly property real graphU: 2.1 - 0.15
        readonly property real denseU: Math.max(1.05 * lineF, 0.8)
        readonly property real colGapU: 1.4                              // between columns (incl. divider)
        function colWidthU(mode) { return mode === "dense" ? 15 : 18.4; }
        // Smallest scale that stays readable; below it the next, more compact view is used
        readonly property real minU: gu * 0.75

        // Split item heights into `cols` consecutive columns with the lowest tallest column.
        function bestSplit(h, cols) {
            const n = h.length;
            const sum = (a, b) => { let t = 0; for (let i = a; i < b; i++) t += h[i]; return t; };
            let best = null;
            const tryBounds = bounds => {
                let tallest = 0;
                for (let i = 0; i + 1 < bounds.length; i++)
                    tallest = Math.max(tallest, sum(bounds[i], bounds[i + 1]));
                if (!best || tallest < best.tallest)
                    best = { bounds: bounds, tallest: tallest };
            };
            if (cols <= 1 || n <= 1)
                tryBounds([0, n]);
            else if (cols === 2 || n === 2)
                for (let a = 1; a < n; a++) tryBounds([0, a, n]);
            else
                for (let a = 1; a < n - 1; a++)
                    for (let b = a + 1; b < n; b++) tryBounds([0, a, b, n]);
            return best;
        }

        // Scale and column layout for one view, or null if it can't apply
        function layoutFor(mode, cols, W, H) {
            const keys = root.metricKeys;
            const n = keys.length;
            if (cols > n)
                return null;
            const gap = mode === "dense" ? denseGapU : gapU;
            const h = keys.map(k => mode === "dense" ? denseU + gap
                                    : rowU + gap + (mode === "graphs" && root.hasGraph(k) ? graphU + gapU : 0));
            const split = bestSplit(h, cols);
            // + gapU: the filler item at the bottom adds one more gap; * 1.02: safety margin
            const neededU = (chromeU + headerU + split.tallest - gap + gapU) * 1.02;
            const widthU = chromeU + cols * colWidthU(mode) + (cols - 1) * colGapU;
            return { mode: mode, cols: cols, bounds: split.bounds, neededU: neededU,
                     u: Math.min(W / widthU, H / neededU) };
        }

        readonly property var plan: {
            const keys = root.metricKeys;
            const n = keys.length;
            const W = width, H = height;
            if (n === 0)
                return { mode: "full", cols: 1, columns: [], u: Math.max(4, Math.min(W / 22, H / 10)) };

            let best = null;
            if (W >= gu * 11 && H >= gu * 5) {
                const anyGraph = keys.some(k => root.hasGraph(k));
                for (const mode of ["graphs", "full", "dense"]) {
                    if (mode === "graphs" && !anyGraph)
                        continue;
                    let choice = null;
                    for (let c = 1; c <= 3; c++) {
                        const l = layoutFor(mode, c, W, H);
                        if (l && (!choice || l.u > choice.u))
                            choice = l;
                    }
                    if (choice && choice.u >= minU) {
                        best = choice;
                        break;
                    }
                }
            }
            if (!best) {
                // tiny: values only, in 1-3 columns (u = value font size)
                // cell = label (0.75 size) + gap + value + column gap. Uses the widest
                // possible value per metric type (not the live text), so the layout
                // doesn't shift as values change.
                const widest = k => (k.startsWith("net") || k === "diskRead" || k === "diskWrite") ? 10 : k === "gpuClock" ? 8
                                  : (k === "gpuPower" || k.endsWith("Temp")) ? 5 : 4;
                const labelChars = Math.max(...keys.map(k => k.startsWith("disk:") ? Math.min(6, root.diskShort(k.slice(5)).length)
                                                          : 5));   // CPU, RAM, C.TMP, G.TMP, G.PWR, G.CLK, VRAM
                const cellW = (labelChars * 0.75 + Math.max(...keys.map(widest))) * charF + 0.3 + 0.8;
                const rowH = lineF + 0.25, chromeT = (0.4 + 0.25 + 0.4) * 2;
                for (let c = 1; c <= Math.min(3, n); c++) {
                    const rows = Math.ceil(n / c);
                    const u = Math.min(W / (chromeT + c * cellW), H / (chromeT + rows * rowH));
                    if (!best || u > best.u)
                        best = { mode: "tiny", cols: c, u: u, bounds: [0, n] };
                }
            }
            best.u = Math.max(3, best.u);
            best.columns = [];
            for (let i = 0; i + 1 < best.bounds.length; i++)
                best.columns.push(keys.slice(best.bounds[i], best.bounds[i + 1]));
            return best;
        }

        readonly property string mode: plan.mode
        readonly property real u: plan.u
        readonly property bool tiny: mode === "tiny"
        readonly property real pad: u * (tiny ? 0.4 : 0.9)
        // Sizes are planned to fit, so text has no fixed minimum here
        readonly property real minText: 0
        function textSize(k) { return u * k; }

        // A new widget (or the panel popup) starts at 20 grid units wide, tall enough
        // for the full view with graphs in one column.
        Layout.preferredWidth: gu * 20
        Layout.preferredHeight: {
            const l = layoutFor("graphs", 1, gu * 20, 1e6) || layoutFor("full", 1, gu * 20, 1e6);
            return l ? Math.ceil(l.neededU * gu * 20 / 22) : gu * 10;
        }
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
            anchors.margins: full.u * (full.tiny ? 0.25 : 0.5)

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

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: full.pad
                spacing: full.u * 0.55

                // ---- header ----
                RowLayout {
                    visible: !full.tiny && root.headerEnabled
                    Layout.fillWidth: true
                    spacing: full.u * 0.5

                    Rectangle {
                        Layout.preferredWidth: full.u * 0.45
                        Layout.preferredHeight: full.u * 0.45
                        color: root.accent
                        opacity: root.blink ? 1 : 0.2
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "SYS.DIAG"
                        font.family: root.fontFamily
                        font.pixelSize: full.textSize(0.85)
                        font.letterSpacing: full.u * 0.08
                        color: root.primary
                        opacity: 0.8
                    }
                    Text {
                        text: root.sensorProblem ? "SENSORS OFFLINE"
                              : "LIVE // " + (root.updateInterval / 1000).toFixed(root.updateInterval % 1000 ? 2 : 1) + "s"
                        font.family: root.fontFamily
                        font.pixelSize: full.textSize(0.85)
                        color: root.accent
                    }
                }

                // ---- divider ----
                Item {
                    visible: !full.tiny && root.headerEnabled
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

                // ---- graphs / full / dense views: 1-3 columns of metrics ----
                RowLayout {
                    visible: !full.tiny && root.metricKeys.length > 0
                    Layout.fillWidth: true
                    spacing: full.u * 0.7

                    Repeater {
                        model: full.tiny ? [] : full.plan.columns
                        RowLayout {
                            id: column
                            required property var modelData     // metric keys in this column
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1             // equal column widths
                            Layout.alignment: Qt.AlignTop
                            spacing: full.u * 0.7

                            Rectangle {
                                visible: column.index > 0
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                color: root.withAlpha(root.primary, 0.25)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: full.mode === "dense" ? full.u * full.denseGapU : full.u * full.gapU

                                Repeater {
                                    model: column.modelData
                                    ColumnLayout {
                                        id: block
                                        required property string modelData   // metric key
                                        readonly property var m: root.metricData[modelData] || root.emptyMetric
                                        Layout.fillWidth: true
                                        spacing: full.u * full.gapU

                                        MetricRow {
                                            visible: full.mode !== "dense"
                                            label: block.m.label
                                            detailText: block.m.detail
                                            valueText: block.m.value
                                            fraction: block.m.fraction
                                            warn: block.m.warn
                                            crit: block.m.crit
                                            blink: root.blink
                                            u: full.u; minText: full.minText
                                            barStyle: root.barStyle
                                            primary: root.primary; warning: root.warning; critical: root.critical; fontFamily: root.fontFamily
                                        }
                                        HistoryGraph {
                                            visible: full.mode === "graphs" && !!block.m.graph
                                            samples: block.m.graph ? block.m.graph.samples : root.noSamples
                                            length: root.historyLength
                                            minValue: block.m.graph ? block.m.graph.min : 0
                                            maxValue: block.m.graph ? block.m.graph.max : 100
                                            warnAt: block.m.graph ? block.m.graph.warnAt : NaN
                                            critAt: block.m.graph ? block.m.graph.critAt : NaN
                                            u: full.u
                                            primary: root.primary; warning: root.warning; critical: root.critical
                                        }
                                        DenseRow {
                                            visible: full.mode === "dense"
                                            label: block.m.short
                                            valueText: block.m.value
                                            fraction: block.m.fraction
                                            warn: block.m.warn
                                            crit: block.m.crit
                                            blink: root.blink
                                            u: full.u
                                            barStyle: root.barStyle
                                            primary: root.primary; warning: root.warning; critical: root.critical; fontFamily: root.fontFamily
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- tiny view: values only ----
                GridLayout {
                    visible: full.tiny
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillHeight: true
                    columns: full.plan.cols
                    columnSpacing: full.u * 0.8
                    rowSpacing: full.u * 0.25

                    Repeater {
                        model: full.tiny ? root.metricKeys : []
                        CompactStat {
                            required property string modelData
                            readonly property var m: root.metricData[modelData] || root.emptyMetric
                            label: m.short
                            valueText: m.value
                            warn: m.warn
                            crit: m.crit
                            primary: root.primary; accent: root.accent; warning: root.warning; critical: root.critical
                            fontFamily: root.fontFamily
                            pixelSize: full.u
                        }
                    }
                }

                // ---- nothing selected ----
                Text {
                    visible: root.metricKeys.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: "NO SENSORS SELECTED\n// CONFIGURE WIDGET"
                    font.family: root.fontFamily
                    font.pixelSize: full.textSize(0.9)
                    color: root.accent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }

                // Absorb extra height so rows stay packed at the top
                Item { Layout.fillHeight: true; visible: !full.tiny }
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
