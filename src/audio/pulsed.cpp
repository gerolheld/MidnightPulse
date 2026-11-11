// SPDX-License-Identifier: MIT
// Midnight Pulse audio daemon.
// Captures Spotify's own PipeWire stream (falls back to the default output monitor),
// feeds it through cava and broadcasts the spectrum + beat energy over a local
// WebSocket (ws://127.0.0.1:47800) so every widget and the wallpaper share ONE capture.
// Audio never touches disk; only bar levels leave this process.
//
// It is also the theme hub: clients on ws://127.0.0.1:47800/theme receive the active colour theme
// ({"t":"theme",mode,preset,custom,speed,h,o,s}) and may send {"t":"set",...} to change it.
// The choice lives in ~/.config/midnight-pulse/theme.json. Mode "cover" follows Spotify's album art;
// "preset"/"custom" also re-colour the static parts (Plasma style, window frames, schemes) through
// ~/.local/share/midnight-pulse/recolor.py.
#include <QCoreApplication>
#include <QProcess>
#include <QTimer>
#include <QTemporaryFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDir>
#include <QFileInfo>
#include <QElapsedTimer>
#include <QWebSocketServer>
#include <QWebSocket>
#include <QHostAddress>
#include <QFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QImage>
#include <QColor>
#include <QUrl>
#include <cmath>

struct Preset { const char *id; double h, o, s; };
static const Preset PRESETS[] = {
    {"midnight", 197, 29, 1.0}, {"neon", 278, 42, 1.0}, {"emerald", 158, 26, 0.92},
    {"sunset", 24, -36, 1.0},   {"crimson", 352, -26, 1.0}, {"arctic", 195, 14, 0.38},
    {"synthwave", 318, -62, 1.0},
    {"ocean", 182, 38, 0.95},
    {"aurora", 145, 115, 0.95},
    {"sakura", 338, 18, 0.55},
    {"amber", 40, -16, 1.0},
    {"lime", 92, 38, 0.95},
    {"lavender", 262, 22, 0.5},
    {"cyber", 52, 110, 1.0},
    {"graphite", 215, 10, 0.12},
    {"mint", 165, 30, 0.55},
    {"inferno", 8, 34, 1.0},
    {"peach", 18, 22, 0.5},
};

static constexpr int BARS = 64;
static constexpr quint16 PORT = 47800;

class Pulsed : public QObject {
    Q_OBJECT
public:
    Pulsed() : m_server("midnight-pulse", QWebSocketServer::NonSecureMode),
               m_config(QDir::tempPath() + "/midnight-pulse-cava-XXXXXX.conf") {
        if (!m_server.listen(QHostAddress::LocalHost, PORT)) {
            qCritical("midnight-pulse: port %d busy", PORT);
            QTimer::singleShot(0, qApp, [] { QCoreApplication::exit(1); });
            return;
        }
        connect(&m_server, &QWebSocketServer::newConnection, this, [this] {
            while (auto *s = m_server.nextPendingConnection()) {
                if (s->requestUrl().path() == "/theme") {
                    m_themeClients << s;
                    connect(s, &QWebSocket::disconnected, this, [this, s] { m_themeClients.removeAll(s); s->deleteLater(); });
                    connect(s, &QWebSocket::textMessageReceived, this, &Pulsed::themeMessage);
                    s->sendTextMessage(themeJson());
                    continue;
                }
                m_clients << s;
                connect(s, &QWebSocket::disconnected, this, [this, s] { m_clients.removeAll(s); s->deleteLater(); });
                s->sendTextMessage(statusJson());
            }
        });
        m_config.open();
        m_config.write(QStringLiteral(
            "[general]\nframerate = 60\nbars = %1\nautosens = 1\n"
            "lower_cutoff_freq = 40\nhigher_cutoff_freq = 14000\nsleep_timer = 0\n"
            "[input]\nmethod = fifo\nsource = /dev/stdin\nsample_rate = 44100\nsample_bits = 16\n"
            "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = binary\n"
            "bit_format = 8bit\nchannels = mono\nmono_option = average\n"
            "[smoothing]\nnoise_reduction = 55\n").arg(BARS).toUtf8());
        m_config.flush();

        connect(&m_cava, &QProcess::readyReadStandardOutput, this, &Pulsed::readFrames);
        for (auto *p : {&m_capture, &m_cava})
            connect(p, &QProcess::finished, this, [this] { if (!m_stopping) scheduleDiscover(1500); });
        connect(&m_query, &QProcess::finished, this, &Pulsed::queryFinished);

        // Re-check every few seconds so we switch to Spotify as soon as it starts playing.
        m_poll.setInterval(4000);
        connect(&m_poll, &QTimer::timeout, this, [this] { if (m_query.state() == QProcess::NotRunning) startQuery(); });
        m_poll.start();
        // Send silence frames while idle so clients decay smoothly.
        m_idle.setInterval(100);
        connect(&m_idle, &QTimer::timeout, this, [this] { if (m_sinceFrame.elapsed() > 300) broadcast(QByteArray(BARS, 0)); });
        m_idle.start();
        m_sinceFrame.start();
        startQuery();

        loadTheme();
        m_coverPoll.setInterval(2000);
        connect(&m_coverPoll, &QTimer::timeout, this, &Pulsed::pollCover);
        m_coverPoll.start();
        m_recolor.setSingleShot(true);
        // the static reload (Plasma style, colour scheme, window frames, cursor) briefly stalls plasmashell, so it
        // waits until the user settles on a colour: every new pick restarts the timer. Live parts recolour at once.
        m_recolor.setInterval(4000);
        connect(&m_recolor, &QTimer::timeout, this, &Pulsed::runRecolor);
    }
    ~Pulsed() override { stop(); }

private:
    QString statusJson() const {
        return QString::fromUtf8(QJsonDocument(QJsonObject{{"t", "status"}, {"source", m_sourceKind}, {"bars", BARS}}).toJson(QJsonDocument::Compact));
    }
    void scheduleDiscover(int ms) { m_target.clear(); QTimer::singleShot(ms, this, [this] { startQuery(); }); }
    void startQuery() {
        if (m_query.state() != QProcess::NotRunning) return;
        m_phase = 0;
        m_query.start("pactl", {"-f", "json", "list", "sink-inputs"});
    }
    void queryFinished() {
        const auto doc = QJsonDocument::fromJson(m_query.readAllStandardOutput());
        if (!doc.isArray()) return;
        if (m_phase == 0) {
            int stream = -1, sink = -1;
            for (const auto &e : doc.array()) {
                const auto o = e.toObject(), pr = o["properties"].toObject();
                const bool spotify = pr["application.name"].toString().contains("spotify", Qt::CaseInsensitive)
                                  || pr["node.name"].toString().contains("spotify", Qt::CaseInsensitive)
                                  || pr["application.process.binary"].toString().contains("spotify", Qt::CaseInsensitive);
                if (spotify && !o["corked"].toBool()) { stream = o["index"].toInt(-1); sink = o["sink"].toInt(-1); break; }
            }
            if (stream >= 0) { m_wantStream = stream; m_wantSink = sink; m_phase = 1; m_query.start("pactl", {"-f", "json", "list", "sinks"}); return; }
            // No Spotify: fall back to whatever the speakers are playing.
            switchTo("monitor", "@DEFAULT_MONITOR@", -1);
        } else {
            for (const auto &e : doc.array()) {
                const auto o = e.toObject();
                if (o["index"].toInt(-2) != m_wantSink) continue;
                QString mon = o["monitor_source_name"].toString();
                if (mon.isEmpty()) mon = o["name"].toString() + ".monitor";
                switchTo("spotify", mon, m_wantStream);
                return;
            }
        }
    }
    void switchTo(const QString &kind, const QString &device, int stream) {
        const QString key = kind + device + QString::number(stream);
        if (key == m_target && m_capture.state() == QProcess::Running) return;
        stop();
        m_target = key; m_sourceKind = kind;
        m_capture.setStandardOutputProcess(&m_cava);
        m_cava.start("cava", {"-p", m_config.fileName()});
        QStringList args{"--device=" + device, "--client-name=Midnight Pulse", "--stream-name=spectrum",
                         "--property=node.virtual=true", "--property=media.role=production",
                         "--raw", "--format=s16le", "--rate=44100", "--channels=2", "--latency-msec=30"};
        if (stream >= 0) args.prepend("--monitor-stream=" + QString::number(stream));
        m_capture.start("parec", args);
        const auto msg = statusJson();
        for (auto *c : m_clients) c->sendTextMessage(msg);
    }
    void stop() {
        m_stopping = true;
        for (auto *p : {&m_capture, &m_cava})
            if (p->state() != QProcess::NotRunning) { p->kill(); p->waitForFinished(300); }
        m_buffer.clear();
        m_stopping = false;
    }
    void readFrames() {
        m_buffer.append(m_cava.readAllStandardOutput());
        if (m_buffer.size() < BARS) return;
        const qsizetype n = m_buffer.size() / BARS;
        const QByteArray latest = m_buffer.mid((n - 1) * BARS, BARS);
        m_buffer.remove(0, n * BARS);
        m_sinceFrame.restart();
        broadcast(latest);
    }
    void broadcast(const QByteArray &frame) {
        if (m_clients.isEmpty()) return;
        // Bass energy = mean of the lowest 6 bars; beat = sharp rise over a slow average.
        double bass = 0, total = 0;
        for (int i = 0; i < BARS; ++i) { double v = (unsigned char)frame[i] / 255.0; total += v; if (i < 6) bass += v; }
        bass /= 6; total /= BARS;
        m_avg = m_avg * 0.92 + bass * 0.08;
        const bool beat = bass > 0.30 && bass > m_avg * 1.30 && (!m_beatClock.isValid() || m_beatClock.elapsed() > 180);
        if (beat) m_beatClock.restart();
        QString s;
        s.reserve(BARS * 3 + 48);
        s += "{\"t\":\"f\",\"b\":" + QString::number(bass, 'f', 3) + ",\"e\":" + QString::number(total, 'f', 3)
           + ",\"k\":" + (beat ? "1" : "0") + ",\"l\":[";
        for (int i = 0; i < BARS; ++i) { if (i) s += ','; s += QString::number((unsigned char)frame[i]); }
        s += "]}";
        for (auto *c : m_clients) c->sendTextMessage(s);
    }


    // ------------------------------------------------------------------ theme
    static QString themePath() {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/midnight-pulse/theme.json";
    }
    void loadTheme() {
        QFile f(themePath());
        if (f.open(QIODevice::ReadOnly)) {
            const auto o = QJsonDocument::fromJson(f.readAll()).object();
            m_mode = o.value("mode").toString("preset");
            m_preset = o.value("preset").toString("midnight");
            m_custom = o.value("custom").toString("#1EB0EA");
            m_speed = o.value("speed").toDouble(1.0);
            m_coverH = o.value("coverH").toDouble(197); m_coverS = o.value("coverS").toDouble(1.0);
        }
        resolve();
    }
    void saveTheme() {
        QDir().mkpath(QFileInfo(themePath()).absolutePath());
        QSaveFile f(themePath());
        if (!f.open(QIODevice::WriteOnly)) return;
        f.write(QJsonDocument(QJsonObject{{"mode", m_mode}, {"preset", m_preset}, {"custom", m_custom}, {"speed", m_speed},
                                          {"coverH", m_coverH}, {"coverS", m_coverS}}).toJson());
        f.commit();
    }
    // turn the current mode into the hue transform (h, o, s)
    void resolve() {
        m_o = 29; m_s = 1.0; m_h = 197;
        if (m_mode == "preset") {
            for (const auto &p : PRESETS) if (m_preset == p.id) { m_h = p.h; m_o = p.o; m_s = p.s; }
        } else if (m_mode == "custom") {
            const QColor c(m_custom);
            if (c.isValid()) { m_h = std::max(0, c.hsvHue()); m_s = std::clamp(c.hsvSaturationF() / 0.87, 0.15, 1.15); }
        } else if (m_mode == "cover") {
            m_h = m_coverH; m_s = m_coverS;
        } else if (m_mode == "rgb") {
            m_h = 197;
        }
    }
    QString themeJson() const {
        return QString::fromUtf8(QJsonDocument(QJsonObject{
            {"t", "theme"}, {"mode", m_mode}, {"preset", m_preset}, {"custom", m_custom}, {"speed", m_speed},
            {"h", m_h}, {"o", m_o}, {"s", m_s}}).toJson(QJsonDocument::Compact));
    }
    void broadcastTheme() { const auto j = themeJson(); for (auto *c : m_themeClients) c->sendTextMessage(j); }
    void themeMessage(const QString &text) {
        const auto o = QJsonDocument::fromJson(text.toUtf8()).object();
        if (o.value("t").toString() != "set") return;
        const QString oldMode = m_mode, oldPreset = m_preset, oldCustom = m_custom;
        if (o.contains("mode")) m_mode = o.value("mode").toString();
        if (o.contains("preset")) m_preset = o.value("preset").toString();
        if (o.contains("custom")) m_custom = o.value("custom").toString();
        if (o.contains("speed")) m_speed = std::clamp(o.value("speed").toDouble(), 0.1, 10.0);
        resolve();
        saveTheme();
        broadcastTheme();
        if (m_mode == "cover") { m_lastArt.clear(); pollCover(); }
        // static parts only follow stable colours (not per-track / rainbow)
        const bool stable = m_mode == "preset" || m_mode == "custom";
        if (stable && (m_mode != oldMode || m_preset != oldPreset || m_custom != oldCustom)) m_recolor.start();
    }
    void runRecolor() {
        const QString script = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/midnight-pulse/recolor.py";
        if (!QFile::exists(script)) return;
        if (m_recolorProc.state() != QProcess::NotRunning) { m_recolor.start(); return; }
        m_recolorProc.start("python3", {script, QString::number(m_h, 'f', 1), QString::number(m_o, 'f', 1), QString::number(m_s, 'f', 3),
                                        m_mode == "preset" ? m_preset : QStringLiteral("custom")});
    }

    // ------------------------------------------------------------------ cover colour
    void pollCover() {
        if (m_mode != "cover") return;
        auto msg = QDBusMessage::createMethodCall("org.mpris.MediaPlayer2.spotify", "/org/mpris/MediaPlayer2",
                                                  "org.freedesktop.DBus.Properties", "Get");
        msg << QStringLiteral("org.mpris.MediaPlayer2.Player") << QStringLiteral("Metadata");
        const auto reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 500);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) return;
        const QVariant v = reply.arguments().first().value<QDBusVariant>().variant();
        QVariantMap meta;
        if (v.canConvert<QDBusArgument>()) v.value<QDBusArgument>() >> meta; else meta = v.toMap();
        const QString art = meta.value("mpris:artUrl").toString();
        if (art.isEmpty() || art == m_lastArt) return;
        m_lastArt = art;
        const QUrl url(art);
        if (url.isLocalFile()) { QImage img(url.toLocalFile()); applyCover(img); return; }
        auto *r = m_net.get(QNetworkRequest(url));
        connect(r, &QNetworkReply::finished, this, [this, r] {
            r->deleteLater();
            QImage img; img.loadFromData(r->readAll());
            applyCover(img);
        });
    }
    void applyCover(const QImage &src) {
        if (src.isNull() || m_mode != "cover") return;
        const QImage img = src.scaled(48, 48, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB32);
        // vote by hue, favouring saturated and reasonably bright pixels → the "vibrant" colour
        double w[36] = {0}, sx[36] = {0}, sy[36] = {0}, ss[36] = {0}, total = 0;
        for (int y = 0; y < img.height(); ++y)
            for (int x = 0; x < img.width(); ++x) {
                const QColor c = QColor::fromRgb(img.pixel(x, y));
                const double sat = c.hsvSaturationF(), val = c.valueF();
                if (sat < 0.22 || val < 0.18 || c.hsvHue() < 0) continue;
                const double wt = sat * sat * val;
                const int b = c.hsvHue() / 10;
                const double a = c.hsvHue() * M_PI / 180.0;
                w[b] += wt; sx[b] += std::cos(a) * wt; sy[b] += std::sin(a) * wt; ss[b] += sat * wt; total += wt;
            }
        if (total < 4.0) {            // grey/black cover → keep the hue, go calm
            m_coverS = 0.32;
        } else {
            int best = 0;
            for (int b = 1; b < 36; ++b) if (w[b] + w[(b + 35) % 36] * 0.5 + w[(b + 1) % 36] * 0.5 > w[best] + w[(best + 35) % 36] * 0.5 + w[(best + 1) % 36] * 0.5) best = b;
            double X = 0, Y = 0, S = 0, W = 0;
            for (int d = -1; d <= 1; ++d) { const int b = (best + d + 36) % 36; X += sx[b]; Y += sy[b]; S += ss[b]; W += w[b]; }
            m_coverH = std::fmod(std::atan2(Y, X) * 180.0 / M_PI + 360.0, 360.0);
            m_coverS = std::clamp((S / W) / 0.87, 0.55, 1.1);
        }
        resolve();
        saveTheme();
        broadcastTheme();
    }

    QWebSocketServer m_server;
    QList<QWebSocket *> m_themeClients;
    QString m_mode = "preset", m_preset = "midnight", m_custom = "#1EB0EA", m_lastArt;
    double m_speed = 1.0, m_h = 197, m_o = 29, m_s = 1.0, m_coverH = 197, m_coverS = 1.0;
    QTimer m_coverPoll, m_recolor;
    QProcess m_recolorProc;
    QNetworkAccessManager m_net;
    QList<QWebSocket *> m_clients;
    QTemporaryFile m_config;
    QProcess m_query, m_capture, m_cava;
    QTimer m_poll, m_idle;
    QElapsedTimer m_sinceFrame, m_beatClock;
    QByteArray m_buffer;
    QString m_target, m_sourceKind = "none";
    int m_phase = 0, m_wantStream = -1, m_wantSink = -1;
    double m_avg = 0;
    bool m_stopping = false;
};

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    qDBusRegisterMetaType<QVariantMap>();
    app.setApplicationName("midnight-pulse-audiod");
    Pulsed d;
    return app.exec();
}
#include "pulsed.moc"
