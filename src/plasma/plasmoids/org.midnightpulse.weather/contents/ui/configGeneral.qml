import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_city: city.text
    Kirigami.FormLayout {
        QQC2.TextField {
            id: city
            Kirigami.FormData.label: "Город:"
            placeholderText: "Например: Warszawa, Москва, Berlin"
        }
        QQC2.Label {
            text: "Погода с open-meteo.com, без ключей и регистрации."
            opacity: 0.7
        }
    }
}
