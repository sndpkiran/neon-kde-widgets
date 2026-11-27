import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.ksysguard.sensors as Sensors

KCM.SimpleKCM {
    id: page

    property alias cfg_showCpu: showCpu.checked
    property alias cfg_showCpuGraph: showCpuGraph.checked
    property alias cfg_showRam: showRam.checked
    property alias cfg_showTemp: showTemp.checked
    property alias cfg_tempSource: tempSource.currentIndex
    property alias cfg_showGpuTemp: showGpuTemp.checked
    property alias cfg_showCpuTempGraph: showCpuTempGraph.checked
    property alias cfg_showGpuTempGraph: showGpuTempGraph.checked
    property alias cfg_showGpuPower: showGpuPower.checked
    property alias cfg_showGpuUsage: showGpuUsage.checked
    property alias cfg_showGpuUsageGraph: showGpuUsageGraph.checked
    property alias cfg_showNetDown: showNetDown.checked
    property alias cfg_showNetUp: showNetUp.checked
    property alias cfg_showNetGraph: showNetGraph.checked
    property alias cfg_netUnit: netUnit.currentIndex
    property alias cfg_showSwap: showSwap.checked
    property alias cfg_showDiskRead: showDiskRead.checked
    property alias cfg_showDiskWrite: showDiskWrite.checked
    property alias cfg_showDiskIoGraph: showDiskIoGraph.checked
    property alias cfg_showGpuPowerGraph: showGpuPowerGraph.checked
    property alias cfg_showGpuClock: showGpuClock.checked
    property alias cfg_showGpuClockGraph: showGpuClockGraph.checked
    property alias cfg_showGpuVram: showGpuVram.checked
    property alias cfg_gpuPowerScale: gpuPowerScale.value
    property alias cfg_vramWarn: vramLevels.warn
    property alias cfg_vramCrit: vramLevels.crit
    property int cfg_gpuIndex
    property alias cfg_showDisk: showDisk.checked
    property alias cfg_mountPoints: mountPoints.text
    property alias cfg_updateInterval: updateInterval.value
    property alias cfg_cpuWarn: cpuLevels.warn
    property alias cfg_cpuCrit: cpuLevels.crit
    property alias cfg_ramWarn: ramLevels.warn
    property alias cfg_ramCrit: ramLevels.crit
    property alias cfg_diskWarn: diskLevels.warn
    property alias cfg_diskCrit: diskLevels.crit
    property alias cfg_cpuTempWarn: cpuTempLevels.warn
    property alias cfg_cpuTempCrit: cpuTempLevels.crit
    property alias cfg_gpuTempWarn: gpuTempLevels.warn
    property alias cfg_gpuTempCrit: gpuTempLevels.crit

    // ---- reset to defaults ----
    // Plasma passes each setting's default value to the page as cfg_<name>Default.
    readonly property var settingKeys: ["showCpu", "showCpuGraph", "showRam", "showTemp", "tempSource", "showGpuTemp", "gpuIndex", "showDisk", "mountPoints", "updateInterval", "cpuWarn", "cpuCrit", "ramWarn", "ramCrit", "diskWarn", "diskCrit", "cpuTempWarn", "cpuTempCrit", "gpuTempWarn", "gpuTempCrit", "showGpuPower", "showGpuClock", "showGpuVram", "gpuPowerScale", "vramWarn", "vramCrit", "showCpuTempGraph", "showGpuTempGraph", "showGpuPowerGraph", "showGpuClockGraph", "showGpuUsage", "showGpuUsageGraph", "showNetDown", "showNetUp", "showNetGraph", "netUnit", "showSwap", "showDiskRead", "showDiskWrite", "showDiskIoGraph"]
    property var cfg_showCpuDefault
    property var cfg_showCpuGraphDefault
    property var cfg_showRamDefault
    property var cfg_showTempDefault
    property var cfg_tempSourceDefault
    property var cfg_showGpuTempDefault
    property var cfg_showCpuTempGraphDefault
    property var cfg_showGpuTempGraphDefault
    property var cfg_showGpuPowerDefault
    property var cfg_showGpuUsageDefault
    property var cfg_showGpuUsageGraphDefault
    property var cfg_showNetDownDefault
    property var cfg_showNetUpDefault
    property var cfg_showNetGraphDefault
    property var cfg_netUnitDefault
    property var cfg_showSwapDefault
    property var cfg_showDiskReadDefault
    property var cfg_showDiskWriteDefault
    property var cfg_showDiskIoGraphDefault
    property var cfg_showGpuPowerGraphDefault
    property var cfg_showGpuClockDefault
    property var cfg_showGpuClockGraphDefault
    property var cfg_showGpuVramDefault
    property var cfg_gpuPowerScaleDefault
    property var cfg_vramWarnDefault
    property var cfg_vramCritDefault
    property var cfg_gpuIndexDefault
    property var cfg_showDiskDefault
    property var cfg_mountPointsDefault
    property var cfg_updateIntervalDefault
    property var cfg_cpuWarnDefault
    property var cfg_cpuCritDefault
    property var cfg_ramWarnDefault
    property var cfg_ramCritDefault
    property var cfg_diskWarnDefault
    property var cfg_diskCritDefault
    property var cfg_cpuTempWarnDefault
    property var cfg_cpuTempCritDefault
    property var cfg_gpuTempWarnDefault
    property var cfg_gpuTempCritDefault
    readonly property bool allDefault: settingKeys.every(k =>
        page["cfg_" + k + "Default"] === undefined
        || String(page["cfg_" + k]) === String(page["cfg_" + k + "Default"]))

    function resetToDefaults() {
        for (const k of settingKeys) {
            const d = page["cfg_" + k + "Default"];
            if (d !== undefined)
                page["cfg_" + k] = d;
        }
    }

    footer: QQC2.Control {
        padding: Kirigami.Units.largeSpacing
        contentItem: RowLayout {
            Item { Layout.fillWidth: true }
            QQC2.Button {
                text: i18n("Reset to Defaults")
                icon.name: "edit-reset"
                enabled: !page.allDefault
                onClicked: page.resetToDefaults()
            }
        }
    }

    // "Warning [  ] %   Critical [  ] %". Warning always stays below critical.
    // Ranges are fixed (not bound to each other) so loading saved values in any
    // order can't clamp them; the ordering is enforced when the user edits.
    component LevelPair: RowLayout {
        id: pair
        property alias warn: warnBox.value
        property alias crit: critBox.value
        property int minimum: 1
        property int maximum: 100
        property string unit: "%"
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: i18n("Warning") }
        QQC2.SpinBox {
            id: warnBox
            from: pair.minimum
            to: pair.maximum - 1
            onValueModified: if (value >= critBox.value) critBox.value = value + 1
        }
        QQC2.Label { text: pair.unit }
        Item { Layout.preferredWidth: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Critical") }
        QQC2.SpinBox {
            id: critBox
            from: pair.minimum + 1
            to: pair.maximum
            onValueModified: if (value <= warnBox.value) warnBox.value = value - 1
        }
        QQC2.Label { text: pair.unit }
    }

    // ---- GPU discovery ----
    // ksystemstats names GPUs gpu/gpu0, gpu/gpu1, … Probe the first few and keep the
    // ones that report a name. Missing ones never error out (they stay "Loading"),
    // so stop waiting after a few seconds.
    property var gpuNames: ({})      // index -> name
    property bool gpuScanDone: false

    Instantiator {
        model: 8
        delegate: Sensors.Sensor {
            required property int index
            sensorId: "gpu/gpu" + index + "/name"
            onValueChanged: {
                if (!value)
                    return;
                const names = Object.assign({}, page.gpuNames);
                names[index] = String(value);
                page.gpuNames = names;
            }
        }
    }
    Timer {
        interval: 4000
        running: true
        onTriggered: page.gpuScanDone = true
    }

    // Dropdown entries: every detected GPU, plus the saved one if it wasn't found
    readonly property var gpuOptions: {
        const scanDone = gpuScanDone;
        const saved = cfg_gpuIndex;
        const found = Object.keys(gpuNames).map(Number);
        const indexes = found.includes(saved) ? found : found.concat([saved]);
        indexes.sort((a, b) => a - b);
        const counts = {};
        for (const i of found) counts[gpuNames[i]] = (counts[gpuNames[i]] || 0) + 1;
        return indexes.map(i => {
            const name = gpuNames[i];
            let text;
            if (name === undefined)
                text = scanDone ? i18n("GPU %1 (not detected)", i) : i18n("Detecting…");
            else
                text = counts[name] > 1 ? name + " #" + i : name;   // tell identical cards apart
            return { value: i, text: text };
        });
    }

    readonly property bool nothingSelected: !showCpu.checked && !showRam.checked && !showTemp.checked
                                            && !showGpuTemp.checked && !showDisk.checked
                                            && !showGpuPower.checked && !showGpuClock.checked && !showGpuVram.checked
                                            && !showGpuUsage.checked && !showNetDown.checked && !showNetUp.checked
                                            && !showSwap.checked && !showDiskRead.checked && !showDiskWrite.checked
    readonly property bool anyGpu: showGpuUsage.checked || showGpuTemp.checked || showGpuPower.checked
                                   || showGpuClock.checked || showGpuVram.checked

    header: Kirigami.InlineMessage {
        visible: page.nothingSelected
        type: Kirigami.MessageType.Warning
        position: Kirigami.InlineMessage.Position.Header
        text: i18n("Nothing is selected. The widget will be empty.")
    }

    Kirigami.FormLayout {
        // ---- what to show ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Show on Widget")
        }

        QQC2.CheckBox {
            id: showCpu
            Kirigami.FormData.label: i18n("Usage:")
            text: i18n("CPU")
        }
        QQC2.CheckBox {
            id: showCpuGraph
            text: i18n("CPU history graph")
            enabled: showCpu.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.CheckBox {
            id: showRam
            text: i18n("RAM")
        }
        QQC2.CheckBox {
            id: showSwap
            text: i18n("Swap")
        }
        QQC2.CheckBox {
            id: showDisk
            text: i18n("Storage space")
        }

        QQC2.CheckBox {
            id: showTemp
            Kirigami.FormData.label: i18n("Temperature:")
            text: i18n("CPU")
        }
        QQC2.CheckBox {
            id: showCpuTempGraph
            text: i18n("CPU temperature history graph")
            enabled: showTemp.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.CheckBox {
            id: showGpuTemp
            text: i18n("GPU")
        }
        QQC2.CheckBox {
            id: showGpuTempGraph
            text: i18n("GPU temperature history graph")
            enabled: showGpuTemp.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }

        QQC2.CheckBox {
            id: showGpuUsage
            Kirigami.FormData.label: i18n("GPU:")
            text: i18n("Usage")
        }
        QQC2.CheckBox {
            id: showGpuUsageGraph
            text: i18n("Usage history graph")
            enabled: showGpuUsage.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.CheckBox {
            id: showGpuPower
            text: i18n("Power draw")
        }
        QQC2.CheckBox {
            id: showGpuPowerGraph
            text: i18n("Power draw history graph")
            enabled: showGpuPower.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.CheckBox {
            id: showGpuClock
            text: i18n("Clock speed")
        }
        QQC2.CheckBox {
            id: showGpuClockGraph
            text: i18n("Clock speed history graph")
            enabled: showGpuClock.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }
        QQC2.CheckBox {
            id: showGpuVram
            text: i18n("VRAM usage")
        }

        QQC2.CheckBox {
            id: showNetDown
            Kirigami.FormData.label: i18n("Network:")
            text: i18n("Download speed")
        }
        QQC2.CheckBox {
            id: showNetUp
            text: i18n("Upload speed")
        }
        QQC2.CheckBox {
            id: showNetGraph
            text: i18n("Network history graphs")
            enabled: showNetDown.checked || showNetUp.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }

        QQC2.CheckBox {
            id: showDiskRead
            Kirigami.FormData.label: i18n("Disk activity:")
            text: i18n("Read speed")
        }
        QQC2.CheckBox {
            id: showDiskWrite
            text: i18n("Write speed")
        }
        QQC2.CheckBox {
            id: showDiskIoGraph
            text: i18n("Disk activity history graphs")
            enabled: showDiskRead.checked || showDiskWrite.checked
            leftPadding: Kirigami.Units.gridUnit * 1.5
        }

        // ---- per-sensor options (only enabled when that sensor is shown) ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Sensor Options")
        }

        QQC2.ComboBox {
            id: tempSource
            Kirigami.FormData.label: i18n("Read CPU temp from:")
            enabled: showTemp.checked
            model: [i18n("Average of all cores"), i18n("Hottest core")]
        }
        QQC2.ComboBox {
            id: gpuBox
            Kirigami.FormData.label: i18n("GPU:")
            enabled: page.anyGpu
            model: page.gpuOptions
            textRole: "text"
            valueRole: "value"
            currentIndex: page.gpuOptions.findIndex(o => o.value === page.cfg_gpuIndex)
            onActivated: {
                page.cfg_gpuIndex = currentValue;
                currentIndex = Qt.binding(() => page.gpuOptions.findIndex(o => o.value === page.cfg_gpuIndex));
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Power bar full at:")
            enabled: showGpuPower.checked
            QQC2.SpinBox {
                id: gpuPowerScale
                from: 0
                to: 1000
                stepSize: 25
                // 0 = Auto
                textFromValue: (value, locale) => value === 0 ? i18n("Auto") : Number(value).toLocaleString(locale, "f", 0)
                valueFromText: (text, locale) => text === i18n("Auto") ? 0 : Number.fromLocaleString(locale, text)
            }
            QQC2.Label {
                visible: gpuPowerScale.value > 0
                text: i18n("W")
            }
        }
        QQC2.Label {
            enabled: showGpuPower.checked
            text: i18n("Auto scales to the highest draw seen since the widget started. For a fixed scale, enter your card's power limit (the sensor doesn't report one).")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
        QQC2.ComboBox {
            id: netUnit
            Kirigami.FormData.label: i18n("Network speed in:")
            enabled: showNetDown.checked || showNetUp.checked
            model: [i18n("Bytes per second (MiB/s)"), i18n("Bits per second (Mbps)")]
        }
        QQC2.TextField {
            id: mountPoints
            Kirigami.FormData.label: i18n("Mount points:")
            enabled: showDisk.checked
            placeholderText: "/, /home, /run/media/…"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.Label {
            enabled: showDisk.checked
            text: i18n("Comma-separated. One bar per mount point.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.SpinBox {
            id: updateInterval
            Kirigami.FormData.label: i18n("Update every (ms):")
            from: 250
            to: 10000
            stepSize: 250
        }

        // ---- alert levels ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Alert Levels")
        }

        LevelPair {
            id: cpuLevels
            Kirigami.FormData.label: i18n("CPU usage:")
            enabled: showCpu.checked
        }
        LevelPair {
            id: ramLevels
            Kirigami.FormData.label: i18n("RAM usage:")
            enabled: showRam.checked
        }
        LevelPair {
            id: diskLevels
            Kirigami.FormData.label: i18n("Storage used:")
            enabled: showDisk.checked
        }
        LevelPair {
            id: vramLevels
            Kirigami.FormData.label: i18n("GPU VRAM used:")
            enabled: showGpuVram.checked
        }

        // Same order as "Show on Widget": usage first, then temperatures
        Item { implicitHeight: Kirigami.Units.largeSpacing }

        LevelPair {
            id: cpuTempLevels
            Kirigami.FormData.label: i18n("CPU temperature:")
            enabled: showTemp.checked
            minimum: 30
            maximum: 110
            unit: "°C"
        }
        LevelPair {
            id: gpuTempLevels
            Kirigami.FormData.label: i18n("GPU temperature:")
            enabled: showGpuTemp.checked
            minimum: 30
            maximum: 110
            unit: "°C"
        }
    }
}
