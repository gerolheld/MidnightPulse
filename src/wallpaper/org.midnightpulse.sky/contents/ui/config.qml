import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_Intensity: intensity.value
    property alias cfg_ShowSpectrum: spectrum.checked
    property alias cfg_ShowParticles: particles.checked
    property alias cfg_ShootingStars: shooting.checked
    property alias cfg_ShowLyrics: lyrics.checked
    QQC2.Slider { id: intensity; Kirigami.FormData.label: "Реакция на музыку:"; from: 0; to: 2; stepSize: 0.1 }
    QQC2.CheckBox { id: spectrum; text: "Светящийся эквалайзер у горизонта" }
    QQC2.CheckBox { id: particles; text: "Светлячки" }
    QQC2.CheckBox { id: shooting; text: "Падающие звёзды на бит" }
    QQC2.CheckBox { id: lyrics; text: "Текст песни (если найден на lrclib.net)" }
}
