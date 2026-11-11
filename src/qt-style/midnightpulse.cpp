// SPDX-License-Identifier: MIT
// Midnight Pulse Qt style: Breeze behaviour + real translucent, blurred glass for selected KDE apps.
#include <QApplication>
#include <QProxyStyle>
#include <QStyleFactory>
#include <QStylePlugin>
#include <QStyleOption>
#include <QPainter>
#include <QPainterPath>
#include <QEvent>
#include <QTimer>
#include <QWindow>
#include <QMainWindow>
#include <QDialog>
#include <KWindowEffects>

static bool glassApp() {
    if (!qApp) return false;
    static const QStringList apps{"dolphin", "systemsettings", "kate", "kwrite", "ark", "kcalc", "filelight", "kinfocenter", "plasma-systemmonitor"};
    const QString n = qApp->applicationName().toLower();
    for (const auto &a : apps) if (n == a) return true;
    return false;
}

class MidnightPulseStyle final : public QProxyStyle {
public:
    MidnightPulseStyle() : QProxyStyle(QStyleFactory::create("Breeze")) { setObjectName("MidnightPulse"); m_glass = glassApp(); }
    void polish(QPalette &pal) override {
        QProxyStyle::polish(pal);
        if (m_glass) tint(pal);
    }
    void polish(QWidget *w) override {
        QProxyStyle::polish(w);
        if (!m_glass) return;
        QPalette pal = w->palette(); tint(pal); w->setPalette(pal);
        const bool top = w->isWindow() && (qobject_cast<QMainWindow *>(w) || qobject_cast<QDialog *>(w) || w->windowType() == Qt::Window);
        if (top && !w->testAttribute(Qt::WA_TranslucentBackground) && w->windowType() != Qt::Popup && w->windowType() != Qt::ToolTip) {
            w->setAttribute(Qt::WA_TranslucentBackground);
            w->setAutoFillBackground(false);
            w->installEventFilter(this);
        }
    }
    void unpolish(QWidget *w) override { w->removeEventFilter(this); QProxyStyle::unpolish(w); }
    bool eventFilter(QObject *o, QEvent *e) override {
        auto *w = qobject_cast<QWidget *>(o);
        if (w && w->isWindow()) {
            if (e->type() == QEvent::Show || e->type() == QEvent::WinIdChange)
                QTimer::singleShot(0, w, [w] { if (w->windowHandle()) KWindowEffects::enableBlurBehind(w->windowHandle(), true); });
            if (e->type() == QEvent::Paint) {
                QPainter p(w);
                QLinearGradient g(0, 0, 0, w->height());
                g.setColorAt(0, QColor(12, 19, 42, 214));
                g.setColorAt(1, QColor(7, 11, 24, 226));
                p.setCompositionMode(QPainter::CompositionMode_Source);
                p.fillRect(w->rect(), g);
            }
        }
        return QProxyStyle::eventFilter(o, e);
    }
    int pixelMetric(PixelMetric m, const QStyleOption *o = nullptr, const QWidget *w = nullptr) const override {
        if (m == PM_ScrollBarExtent) return 10;
        return QProxyStyle::pixelMetric(m, o, w);
    }
    void drawPrimitive(PrimitiveElement e, const QStyleOption *o, QPainter *p, const QWidget *w = nullptr) const override {
        if (m_glass && (e == PE_PanelMenuBar || e == PE_PanelToolBar || e == PE_FrameStatusBarItem)) return;
        QProxyStyle::drawPrimitive(e, o, p, w);
    }
private:
    static void tint(QPalette &pal) {
        for (auto g : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
            pal.setColor(g, QPalette::Window, QColor(10, 16, 36, 0));
            pal.setColor(g, QPalette::Base, QColor(7, 11, 24, 70));
            pal.setColor(g, QPalette::AlternateBase, QColor(26, 42, 85, 60));
        }
    }
    bool m_glass = false;
};

class MidnightPulsePlugin final : public QStylePlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QStyleFactoryInterface" FILE "midnightpulse.json")
public:
    QStyle *create(const QString &key) override { return key.compare("MidnightPulse", Qt::CaseInsensitive) == 0 ? new MidnightPulseStyle : nullptr; }
};
#include "midnightpulse.moc"
