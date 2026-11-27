import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_locationName
    property real cfg_latitude
    property real cfg_longitude
    property alias cfg_tempUnit: tempUnit.currentIndex
    property alias cfg_windUnit: windUnit.currentIndex
    property alias cfg_showDetails: showDetails.checked
    property alias cfg_showCity: showCity.checked
    property alias cfg_showHourly: showHourly.checked
    property alias cfg_showDaily: showDaily.checked
    property alias cfg_dailyDays: dailyDays.value
    property alias cfg_refreshMinutes: refreshMinutes.value

    // ---- reset to defaults ----
    // Plasma passes each setting's default value to the page as cfg_<name>Default.
    // The location is left alone: resetting it would just leave the widget empty.
    readonly property var settingKeys: ["tempUnit", "windUnit", "showCity", "showDetails", "showHourly",
                                        "showDaily", "dailyDays", "refreshMinutes"]
    property var cfg_tempUnitDefault
    property var cfg_windUnitDefault
    property var cfg_showDetailsDefault
    property var cfg_showCityDefault
    property var cfg_showHourlyDefault
    property var cfg_showDailyDefault
    property var cfg_dailyDaysDefault
    property var cfg_refreshMinutesDefault
    property var cfg_locationNameDefault
    property var cfg_latitudeDefault
    property var cfg_longitudeDefault

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

    header: Kirigami.InlineMessage {
        visible: true
        type: Kirigami.MessageType.Information
        position: Kirigami.InlineMessage.Position.Header
        text: i18n("Weather comes from Open-Meteo.com, an online service. Your chosen location is sent with each update. See Data Source below.")
    }

    // ---- city search (Open-Meteo geocoding) ----
    property var results: []
    property string searchState: ""     // "", "searching", "none", "error"

    function search() {
        const query = searchField.text.trim();
        if (query.length < 2)
            return;
        searchState = "searching";
        results = [];
        const lang = Qt.locale().name.split("_")[0] || "en";
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            try {
                const data = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
                if (!data) {
                    searchState = "error";
                    return;
                }
                results = data.results || [];
                searchState = results.length ? "" : "none";
            } catch (e) {
                searchState = "error";
            }
        };
        xhr.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=8&format=json"
                 + "&language=" + encodeURIComponent(lang)
                 + "&name=" + encodeURIComponent(query));
        xhr.send();
    }

    function placeLabel(r) {
        return [r.name, r.admin1, r.country].filter(s => s && s.length).join(", ");
    }

    Kirigami.FormLayout {
        // ---- location ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Location")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Current:")
            text: page.cfg_locationName
                  ? page.cfg_locationName + "  (" + page.cfg_latitude.toFixed(2) + ", " + page.cfg_longitude.toFixed(2) + ")"
                  : i18n("Not set")
            font.bold: page.cfg_locationName !== ""
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Find a city:")
            QQC2.TextField {
                id: searchField
                placeholderText: i18n("City name…")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                onAccepted: page.search()
            }
            QQC2.Button {
                text: i18n("Search")
                icon.name: "search"
                enabled: searchField.text.trim().length >= 2 && page.searchState !== "searching"
                onClicked: page.search()
            }
        }

        QQC2.Label {
            visible: page.searchState !== ""
            text: page.searchState === "searching" ? i18n("Searching…")
                : page.searchState === "none" ? i18n("No places found.")
                : i18n("Search failed. Check your connection and try again.")
            opacity: 0.7
        }

        // Search results: click one to use it
        ColumnLayout {
            visible: page.results.length > 0
            spacing: 0
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20

            Repeater {
                model: page.results
                QQC2.ItemDelegate {
                    required property var modelData
                    Layout.fillWidth: true
                    text: page.placeLabel(modelData)
                    icon.name: "mark-location"
                    onClicked: {
                        page.cfg_locationName = page.placeLabel(modelData);
                        page.cfg_latitude = modelData.latitude;
                        page.cfg_longitude = modelData.longitude;
                        page.results = [];
                        searchField.text = "";
                    }
                }
            }
        }

        // ---- units ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Units")
        }

        QQC2.ComboBox {
            id: tempUnit
            Kirigami.FormData.label: i18n("Temperature:")
            model: [i18n("Automatic (from locale)"), i18n("Celsius (°C)"), i18n("Fahrenheit (°F)")]
        }
        QQC2.ComboBox {
            id: windUnit
            Kirigami.FormData.label: i18n("Wind speed:")
            model: [i18n("Automatic (from locale)"), i18n("km/h"), i18n("m/s"), i18n("mph"), i18n("Knots")]
        }

        // ---- what to show ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Show on Widget")
        }

        QQC2.CheckBox {
            id: showCity
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("City name")
        }
        QQC2.CheckBox {
            id: showDetails
            text: i18n("Details (feels like, humidity, wind, pressure, sun)")
        }
        QQC2.CheckBox {
            id: showHourly
            text: i18n("Next 24 hours graph")
        }
        QQC2.CheckBox {
            id: showDaily
            text: i18n("Daily forecast")
        }
        QQC2.SpinBox {
            id: dailyDays
            Kirigami.FormData.label: i18n("Forecast days:")
            enabled: showDaily.checked
            from: 3
            to: 7
        }

        // ---- updates ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Updates")
        }

        QQC2.SpinBox {
            id: refreshMinutes
            Kirigami.FormData.label: i18n("Refresh every (min):")
            from: 10
            to: 180
            stepSize: 5
        }

        // ---- data source / disclosure ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Data Source")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Weather:")
            text: i18n("<a href=\"https://open-meteo.com/\">Open-Meteo.com</a>, licensed under <a href=\"https://creativecommons.org/licenses/by/4.0/\">CC BY 4.0</a>.")
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("City search:")
            text: i18n("Open-Meteo, using <a href=\"https://www.geonames.org/\">GeoNames</a> data.")
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("What's sent:")
            text: i18n("• Each update: the location's coordinates, rounded to about 1 km.\n• Each search: the city name you typed.\nNothing else. Nothing is sent until a location is set.")
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }
        QQC2.Label {
            text: i18n("Open-Meteo's <a href=\"https://open-meteo.com/en/terms\">terms and privacy policy</a> apply.")
            textFormat: Text.StyledText
            font: Kirigami.Theme.smallFont
            opacity: 0.8
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }
}
