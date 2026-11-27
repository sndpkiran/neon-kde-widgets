import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.private.mpris as Mpris

KCM.SimpleKCM {
    id: page

    property alias cfg_artStyle: artStyle.currentIndex
    property alias cfg_showAlbum: showAlbum.checked
    property alias cfg_glitchOnChange: glitchOnChange.checked
    property alias cfg_showVolume: showVolume.checked
    property alias cfg_showRemaining: showRemaining.checked
    property alias cfg_ignoreBrowsers: ignoreBrowsers.checked
    property alias cfg_ignoredPlayers: ignoredPlayers.text
    property alias cfg_preferredPlayer: preferredPlayer.text
    property alias cfg_artAccent: artAccent.checked
    property alias cfg_artBackdrop: artBackdrop.checked
    property alias cfg_showShuffleRepeat: showShuffleRepeat.checked

    // ---- reset to defaults ----
    // Plasma passes each setting's default value to the page as cfg_<name>Default.
    readonly property var settingKeys: ["artStyle", "artAccent", "artBackdrop", "showAlbum", "showVolume", "showRemaining", "showShuffleRepeat", "glitchOnChange", "ignoreBrowsers", "ignoredPlayers", "preferredPlayer"]
    property var cfg_artStyleDefault
    property var cfg_showAlbumDefault
    property var cfg_glitchOnChangeDefault
    property var cfg_showVolumeDefault
    property var cfg_showRemainingDefault
    property var cfg_ignoreBrowsersDefault
    property var cfg_ignoredPlayersDefault
    property var cfg_preferredPlayerDefault

    // Players open right now, listed under the name fields so users know what to type
    Mpris.Mpris2Model { id: mpris }
    Instantiator {
        id: openPlayers
        model: mpris
        delegate: QtObject {
            required property bool isMultiplexer
            required property string identity
        }
    }
    readonly property string openPlayerNames: {
        const names = [];
        for (let i = 0; i < openPlayers.count; i++) {
            const e = openPlayers.objectAt(i);
            if (e && !e.isMultiplexer && e.identity && !names.includes(e.identity))
                names.push(e.identity);
        }
        return names.join(", ");
    }
    property var cfg_artAccentDefault
    property var cfg_artBackdropDefault
    property var cfg_showShuffleRepeatDefault

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

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: artStyle
            Kirigami.FormData.label: i18n("Album art:")
            model: [i18n("Neon tint"), i18n("Original colors"), i18n("Hidden")]
        }
        QQC2.CheckBox {
            id: artAccent
            text: i18n("Take accent color from album art")
        }
        QQC2.CheckBox {
            id: artBackdrop
            text: i18n("Blurred album art behind the widget")
        }
        QQC2.CheckBox {
            id: showAlbum
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Album name")
        }
        QQC2.CheckBox {
            id: showVolume
            text: i18n("Volume bar")
        }
        QQC2.CheckBox {
            id: showRemaining
            text: i18n("Time left instead of track length")
        }
        QQC2.CheckBox {
            id: showShuffleRepeat
            text: i18n("Shuffle and repeat buttons")
        }
        QQC2.CheckBox {
            id: glitchOnChange
            Kirigami.FormData.label: i18n("Effects:")
            text: i18n("Glitch when the track changes")
        }

        // ---- which player to show ----
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Players")
        }
        QQC2.CheckBox {
            id: ignoreBrowsers
            Kirigami.FormData.label: i18n("Ignore:")
            text: i18n("Web browsers (YouTube tabs, videos on websites…)")
        }
        QQC2.TextField {
            id: ignoredPlayers
            Kirigami.FormData.label: i18n("Also ignore:")
            placeholderText: i18n("e.g. vlc, elisa")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.TextField {
            id: preferredPlayer
            Kirigami.FormData.label: i18n("Prefer:")
            placeholderText: i18n("e.g. spotify")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.Label {
            text: page.openPlayerNames ? i18n("Open now: %1", page.openPlayerNames) : i18n("No players open right now.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
        QQC2.Label {
            text: i18n("Names are comma-separated and not case-sensitive. The preferred player is shown when it's playing or when nothing else is; ignored players are never shown.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Label {
            text: i18n("Shows whichever media player is active (Spotify, browsers, VLC, mpv…). Scroll over the widget to change volume; middle-click to play or pause; click the album art to bring the player's window to the front; drag along the progress bar to seek; click the track length to show the time left. With several players open, click the player name in the header to switch between them.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
