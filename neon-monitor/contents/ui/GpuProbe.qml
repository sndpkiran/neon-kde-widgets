import QtQuick
import org.kde.ksysguard.sensors as Sensors

// Created at runtime so the settings page opens without the sensors module.
QtObject {
    id: probe

    property var names: ({})      // index -> name

    readonly property Instantiator sensors: Instantiator {
        model: 8
        delegate: Sensors.Sensor {
            id: gpuName
            required property int index
            sensorId: "gpu/gpu" + gpuName.index + "/name"
            onValueChanged: {
                if (!gpuName.value)
                    return;
                const names = Object.assign({}, probe.names);
                names[gpuName.index] = String(gpuName.value);
                probe.names = names;
            }
        }
    }
}
