import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    id: page

    property alias cfg_style: styleBox.currentIndex
    property alias cfg_showBorder: showBorder.checked
    property alias cfg_showHeader: showHeader.checked
    property alias cfg_primaryColor: primaryColor.color
    property alias cfg_accentColor: accentColor.color
    property alias cfg_criticalColor: criticalColor.color
    property alias cfg_warningSameAsAccent: warningSame.checked
    property alias cfg_warningColor: warningColor.color
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_glow: glow.checked
    property alias cfg_scanlines: scanlines.checked
    property alias cfg_scanSweep: scanSweep.checked
    property string cfg_fontFamily

    // ---- reset to defaults ----
    // Plasma passes each setting's default value to the page as cfg_<name>Default.
    readonly property var settingKeys: ["style", "showBorder", "showHeader", "primaryColor", "accentColor", "warningSameAsAccent", "warningColor", "criticalColor", "backgroundOpacity", "glow", "scanlines", "scanSweep", "fontFamily"]
    property var cfg_styleDefault
    property var cfg_showBorderDefault
    property var cfg_showHeaderDefault
    property var cfg_primaryColorDefault
    property var cfg_accentColorDefault
    property var cfg_criticalColorDefault
    property var cfg_warningSameAsAccentDefault
    property var cfg_warningColorDefault
    property var cfg_backgroundOpacityDefault
    property var cfg_glowDefault
    property var cfg_scanlinesDefault
    property var cfg_scanSweepDefault
    property var cfg_fontFamilyDefault
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

    readonly property var presets: [
        { name: i18n("Neon Night (cyan / magenta)"), primary: "#00f0ff", accent: "#ff2a6d", critical: "#ff1a1a" },
        { name: i18n("Chrome (white / cyan)"),       primary: "#e8f1ff", accent: "#00f0ff", critical: "#ff1a1a" },
        { name: i18n("Synthwave (pink / blue)"),     primary: "#ff71ce", accent: "#01cdfe", critical: "#ff1a1a" },
        { name: i18n("Toxic (green / yellow)"),      primary: "#39ff14", accent: "#fcee0a", critical: "#ff1a1a" },
        { name: i18n("Amber terminal"),              primary: "#ffb000", accent: "#ff3c00", critical: "#ff1a1a" },
        { name: i18n("Redline (red / cyan)"),        primary: "#ff003c", accent: "#00f0ff", critical: "#fcee0a" }
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: styleBox
            Kirigami.FormData.label: i18n("Style:")
            model: [i18n("Panel (solid HUD box)"), i18n("Holo (blend into wallpaper)")]
        }
        QQC2.CheckBox {
            id: showBorder
            Kirigami.FormData.label: i18n("Border:")
            text: i18n("Show frame and accent tabs")
        }
        QQC2.CheckBox {
            id: showHeader
            Kirigami.FormData.label: i18n("Header:")
            text: i18n("Show header")
        }
        QQC2.ComboBox {
            id: presetBox
            Kirigami.FormData.label: i18n("Color preset:")
            // Show the preset that matches the current colors, or "Custom" if none does
            readonly property int matchedIndex: {
                const i = page.presets.findIndex(p =>
                    Qt.colorEqual(p.primary, primaryColor.color) &&
                    Qt.colorEqual(p.accent, accentColor.color) &&
                    Qt.colorEqual(p.critical, criticalColor.color));
                return i >= 0 ? i : page.presets.length;
            }
            model: page.presets.map(p => p.name).concat([i18n("Custom")])
            currentIndex: matchedIndex
            onActivated: index => {
                if (index < page.presets.length) {
                    const p = page.presets[index];
                    primaryColor.color = p.primary;
                    accentColor.color = p.accent;
                    criticalColor.color = p.critical;
                }
                // Picking an item can replace the binding; restore it so the box
                // keeps following the colors (and "Custom" snaps back to a match).
                currentIndex = Qt.binding(() => presetBox.matchedIndex);
            }
        }
        KQuickControls.ColorButton {
            id: primaryColor
            Kirigami.FormData.label: i18n("Neon color:")
            showAlphaChannel: false
        }
        KQuickControls.ColorButton {
            id: accentColor
            Kirigami.FormData.label: i18n("Accent color:")
            showAlphaChannel: false
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Warning color:")
            QQC2.CheckBox {
                id: warningSame
                text: i18n("Same as accent")
            }
            // only shown when warnings get their own color
            KQuickControls.ColorButton {
                id: warningColor
                visible: !warningSame.checked
                showAlphaChannel: false
            }
        }
        KQuickControls.ColorButton {
            id: criticalColor
            Kirigami.FormData.label: i18n("Critical color:")
            showAlphaChannel: false
        }
        QQC2.SpinBox {
            id: backgroundOpacity
            Kirigami.FormData.label: styleBox.currentIndex === 1 ? i18n("Backdrop opacity (%):") : i18n("Panel opacity (%):")
            from: 0
            to: 100
            stepSize: 5
        }
        QQC2.ComboBox {
            id: fontBox
            Kirigami.FormData.label: i18n("Font:")
            model: [i18n("Default monospace")].concat(Qt.fontFamilies())
            // Follow cfg_fontFamily (so Reset to Defaults shows up here too)
            readonly property int savedIndex: {
                const n = count;   // re-check once the font list is loaded
                const idx = find(page.cfg_fontFamily);
                return (page.cfg_fontFamily === "" || idx < 0) ? 0 : idx;
            }
            currentIndex: savedIndex
            onActivated: index => {
                page.cfg_fontFamily = index === 0 ? "" : currentText;
                currentIndex = Qt.binding(() => fontBox.savedIndex);
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: glow
            Kirigami.FormData.label: i18n("Effects:")
            text: i18n("Neon glow")
        }
        QQC2.CheckBox {
            id: scanlines
            text: i18n("Scanlines")
        }
        QQC2.CheckBox {
            id: scanSweep
            text: i18n("Moving scan band")
        }
    }
}
