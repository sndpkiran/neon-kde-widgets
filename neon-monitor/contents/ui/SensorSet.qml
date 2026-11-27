import QtQuick
import org.kde.ksysguard.sensors as Sensors

// Created at runtime so a missing sensors module doesn't break the widget.
QtObject {
    id: set

    required property var host

    // Exists everywhere: no value means ksystemstats isn't running.
    readonly property QtObject probeSensor: Sensors.Sensor {
        sensorId: "memory/physical/total"
    }

    readonly property QtObject cpuSensor: Sensors.Sensor {
        sensorId: "cpu/all/usage"
        enabled: set.host.showCpu
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject cpuFreqSensor: Sensors.Sensor {
        sensorId: "cpu/all/averageFrequency"
        enabled: set.host.showCpu
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject ramSensor: Sensors.Sensor {
        sensorId: "memory/physical/usedPercent"
        enabled: set.host.showRam
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject ramUsedSensor: Sensors.Sensor {
        sensorId: "memory/physical/used"
        enabled: set.host.showRam
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject ramTotalSensor: Sensors.Sensor {
        sensorId: "memory/physical/total"
        enabled: set.host.showRam
    }
    readonly property QtObject tempSensor: Sensors.Sensor {
        sensorId: set.host.tempSensorId
        enabled: set.host.showTemp
        updateRateLimit: set.host.updateInterval
    }

    readonly property QtObject gpuTempSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/temperature"
        enabled: set.host.showGpuTemp
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject gpuNameSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/name"
        enabled: set.host.anyGpu
    }
    readonly property QtObject gpuUsageSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/usage"
        enabled: set.host.showGpuUsage
        updateRateLimit: set.host.updateInterval
    }

    // Network: all interfaces combined (bytes per second; totals in bytes)
    readonly property QtObject netDownSensor: Sensors.Sensor {
        sensorId: "network/all/download"
        enabled: set.host.showNetDown
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject netUpSensor: Sensors.Sensor {
        sensorId: "network/all/upload"
        enabled: set.host.showNetUp
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject netTotalDownSensor: Sensors.Sensor {
        sensorId: "network/all/totalDownload"
        enabled: set.host.showNetDown
    }
    // Swap (bytes, %) and disk activity across all disks (bytes per second)
    readonly property QtObject swapSensor: Sensors.Sensor {
        sensorId: "memory/swap/usedPercent"
        enabled: set.host.showSwap
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject swapUsedSensor: Sensors.Sensor {
        sensorId: "memory/swap/used"
        enabled: set.host.showSwap
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject swapTotalSensor: Sensors.Sensor {
        sensorId: "memory/swap/total"
        enabled: set.host.showSwap
    }
    readonly property QtObject diskReadSensor: Sensors.Sensor {
        sensorId: "disk/all/read"
        enabled: set.host.showDiskRead
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject diskWriteSensor: Sensors.Sensor {
        sensorId: "disk/all/write"
        enabled: set.host.showDiskWrite
        updateRateLimit: set.host.updateInterval
    }

    readonly property QtObject netTotalUpSensor: Sensors.Sensor {
        sensorId: "network/all/totalUpload"
        enabled: set.host.showNetUp
    }

    readonly property QtObject gpuPowerSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/power"
        enabled: set.host.showGpuPower
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject gpuClockSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/coreFrequency"
        enabled: set.host.showGpuClock
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject gpuVramSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/usedPercent"
        enabled: set.host.showGpuVram
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject gpuVramUsedSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/usedVram"
        enabled: set.host.showGpuVram
        updateRateLimit: set.host.updateInterval
    }
    readonly property QtObject gpuVramTotalSensor: Sensors.Sensor {
        sensorId: set.host.gpuSensorBase + "/totalVram"
        enabled: set.host.showGpuVram
    }
}
