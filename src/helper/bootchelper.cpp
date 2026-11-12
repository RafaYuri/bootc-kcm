#include "bootchelper.h"

#include <KAuth/HelperSupport>

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStringList>

BootcHelper::BootcHelper(QObject *parent)
    : QObject(parent)
{
}

bool BootcHelper::isAutoTimerEnabled() const
{
    QProcess proc;
    proc.start(QStringLiteral("/usr/bin/systemctl"),
               {QStringLiteral("is-enabled"), QStringLiteral("bootc-fetch-apply-updates.timer")});
    proc.waitForFinished(5000);
    const QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    return out == QLatin1String("enabled") || out == QLatin1String("static") || out == QLatin1String("enabled-runtime");
}

bool BootcHelper::isUnitRunning(const QString &unitName) const
{
    QProcess proc;
    proc.start(QStringLiteral("/usr/bin/systemctl"),
               {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("ActiveState"),
                QStringLiteral("-p"), QStringLiteral("SubState"), QStringLiteral("--value"), unitName});
    proc.waitForFinished(5000);
    const QStringList lines = QString::fromUtf8(proc.readAllStandardOutput())
                                  .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    const QString activeState = lines.value(0).trimmed();
    const QString subState = lines.value(1).trimmed();
    return activeState == QLatin1String("activating")
           || (activeState == QLatin1String("active") && subState == QLatin1String("running"));
}

QString BootcHelper::activeUpgradeUnit() const
{
    const QStringList units = {
        QStringLiteral("bootc-kcm-upgrade.service"),
        QStringLiteral("bootc-fetch-apply-updates.service")
    };
    for (const QString &unit : units) {
        if (isUnitRunning(unit)) {
            return unit;
        }
    }
    return {};
}

void BootcHelper::syncRebootRequiredMarker(const QByteArray &statusJson) const
{
    QJsonParseError parseErr{};
    const QJsonDocument doc = QJsonDocument::fromJson(statusJson, &parseErr);
    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        return;
    }

    const QJsonObject root = doc.object();
    const QJsonObject statusObj = root.value(QStringLiteral("status")).toObject();
    const bool hasStaged = !statusObj.value(QStringLiteral("staged")).isNull()
                           && statusObj.value(QStringLiteral("staged")).isObject();
    const bool rollbackQueued = statusObj.value(QStringLiteral("rollbackQueued")).toBool(false);

    QFile marker(QStringLiteral("/run/reboot-required"));
    if (hasStaged || rollbackQueued) {
        if (!marker.exists()) {
            if (marker.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                marker.write("bootc\n");
                marker.close();
            }
        }
    } else if (marker.exists()) {
        // Se não há staged nem rollback, e o marcador foi gerado pelo bootc, remove de forma limpa
        if (marker.open(QIODevice::ReadOnly)) {
            const QByteArray content = marker.readAll();
            marker.close();
            if (content.startsWith("bootc")) {
                marker.remove();
            }
        }
    }
}

QVariantMap BootcHelper::collectStatusPayload(QString *errorOut) const
{
    QVariantMap data;

    QProcess proc;
    proc.start(QStringLiteral("/usr/bin/bootc"),
               {QStringLiteral("status"), QStringLiteral("--format=json")});

    if (!proc.waitForFinished(30000)) {
        if (errorOut) {
            *errorOut = QStringLiteral("Tempo limite excedido ao executar 'bootc status --format=json'.");
        }
        return data;
    }

    const QByteArray stdoutBytes = proc.readAllStandardOutput();
    const QByteArray stderrBytes = proc.readAllStandardError();

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        if (errorOut) {
            *errorOut = QString::fromUtf8(stderrBytes.isEmpty() ? stdoutBytes : stderrBytes).trimmed();
        }
        return data;
    }

    syncRebootRequiredMarker(stdoutBytes);

    data.insert(QStringLiteral("statusJson"), QString::fromUtf8(stdoutBytes));
    data.insert(QStringLiteral("rebootRequiredFile"), QFileInfo::exists(QStringLiteral("/run/reboot-required")));
    data.insert(QStringLiteral("autoTimerEnabled"), isAutoTimerEnabled());
    data.insert(QStringLiteral("upgradeInProgress"), !activeUpgradeUnit().isEmpty());
    return data;
}

ActionReply BootcHelper::status(const QVariantMap &args)
{
    Q_UNUSED(args);

    QString err;
    const QVariantMap payload = collectStatusPayload(&err);
    if (payload.isEmpty()) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(err.isEmpty() ? QStringLiteral("Falha ao obter status do bootc.") : err);
        return reply;
    }

    ActionReply reply = ActionReply::SuccessReply();
    reply.setData(payload);
    return reply;
}

ActionReply BootcHelper::check(const QVariantMap &args)
{
    Q_UNUSED(args);

    HelperSupport::progressStep(QVariantMap{
        {QStringLiteral("line"), QStringLiteral("Consultando registro remoto por novas camadas da imagem (bootc upgrade --check)...")}
    });

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(QStringLiteral("/usr/bin/bootc"),
               {QStringLiteral("upgrade"), QStringLiteral("--check")});

    QString fullOutput;
    while (!proc.waitForFinished(250)) {
        if (HelperSupport::isStopped()) {
            proc.terminate();
            proc.waitForFinished(2000);
            ActionReply reply = ActionReply::HelperErrorReply();
            reply.setErrorDescription(QStringLiteral("Verificação cancelada pelo usuário."));
            return reply;
        }
        while (proc.canReadLine()) {
            const QString line = QString::fromUtf8(proc.readLine()).trimmed();
            if (!line.isEmpty()) {
                fullOutput += line + QLatin1Char('\n');
                HelperSupport::progressStep(QVariantMap{{QStringLiteral("line"), line}});
            }
        }
    }

    const QString remaining = QString::fromUtf8(proc.readAll()).trimmed();
    if (!remaining.isEmpty()) {
        fullOutput += remaining + QLatin1Char('\n');
        for (const QString &line : remaining.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            HelperSupport::progressStep(QVariantMap{{QStringLiteral("line"), line.trimmed()}});
        }
    }

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(fullOutput.trimmed().isEmpty()
                                      ? QStringLiteral("Erro ao verificar atualizações com 'bootc upgrade --check'.")
                                      : fullOutput.trimmed());
        return reply;
    }

    QString statusErr;
    QVariantMap payload = collectStatusPayload(&statusErr);
    payload.insert(QStringLiteral("commandOutput"), fullOutput.trimmed());

    // Detecta se a saída textual do 'bootc upgrade --check' indica ausência de mudanças
    const QString lowerOut = fullOutput.toLower();
    const bool noChanges = lowerOut.contains(QLatin1String("no changes"))
                           || lowerOut.contains(QLatin1String("already at latest"))
                           || lowerOut.contains(QLatin1String("up to date"));
    payload.insert(QStringLiteral("checkReportedUpdate"), !noChanges && !fullOutput.trimmed().isEmpty());

    ActionReply reply = ActionReply::SuccessReply();
    reply.setData(payload);
    return reply;
}

ActionReply BootcHelper::upgrade(const QVariantMap &args)
{
    Q_UNUSED(args);

    QString unitName = activeUpgradeUnit();
    const bool alreadyRunning = !unitName.isEmpty();

    if (!alreadyRunning) {
        unitName = QStringLiteral("bootc-kcm-upgrade.service");
        QProcess::execute(QStringLiteral("/usr/bin/systemctl"),
                          {QStringLiteral("reset-failed"), unitName});

        QProcess startProc;
        startProc.setProcessChannelMode(QProcess::MergedChannels);
        startProc.start(QStringLiteral("/usr/bin/systemd-run"), {
            QStringLiteral("--unit=") + unitName,
            QStringLiteral("--description=Bootc KCM System Update"),
            QStringLiteral("--property=Type=exec"),
            QStringLiteral("--property=ExecStopPost=-/usr/bin/bootc-notify --sync-marker"),
            QStringLiteral("/usr/bin/bootc"),
            QStringLiteral("upgrade")
        });

        if (!startProc.waitForFinished(15000) || startProc.exitStatus() != QProcess::NormalExit || startProc.exitCode() != 0) {
            const QString startErr = QString::fromUtf8(startProc.readAll()).trimmed();
            ActionReply reply = ActionReply::HelperErrorReply();
            reply.setErrorDescription(startErr.isEmpty()
                                          ? QStringLiteral("Não foi possível iniciar a atualização em segundo plano.")
                                          : startErr);
            return reply;
        }

        HelperSupport::progressStep(QVariantMap{
            {QStringLiteral("line"), QStringLiteral("Iniciando download e preparação da imagem...")}
        });
    } else {
        HelperSupport::progressStep(QVariantMap{
            {QStringLiteral("line"), QStringLiteral("Acompanhando atualização em andamento em segundo plano...")}
        });
    }

    QProcess idProc;
    idProc.start(QStringLiteral("/usr/bin/systemctl"),
                 {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("InvocationID"),
                  QStringLiteral("--value"), unitName});
    idProc.waitForFinished(3000);
    const QString invocationId = QString::fromUtf8(idProc.readAllStandardOutput()).trimmed();

    QStringList journalArgs{
        QStringLiteral("-u"), unitName,
        QStringLiteral("-f"),
        QStringLiteral("-n"), QStringLiteral("50"),
        QStringLiteral("--output=cat")
    };
    if (!invocationId.isEmpty()) {
        journalArgs << (QStringLiteral("_SYSTEMD_INVOCATION_ID=") + invocationId);
    }

    QProcess journalProc;
    journalProc.setProcessChannelMode(QProcess::MergedChannels);
    journalProc.start(QStringLiteral("/usr/bin/journalctl"), journalArgs);

    QString fullOutput;
    auto drainJournal = [&]() {
        while (journalProc.canReadLine()) {
            const QString line = QString::fromUtf8(journalProc.readLine()).trimmed();
            if (!line.isEmpty()) {
                fullOutput += line + QLatin1Char('\n');
                HelperSupport::progressStep(QVariantMap{{QStringLiteral("line"), line}});
            }
        }
    };

    while (isUnitRunning(unitName)) {
        if (HelperSupport::isStopped()) {
            // Desacoplado: não interrompe a unit systemd para que a atualização continue em segundo plano
            journalProc.terminate();
            journalProc.waitForFinished(1000);
            return ActionReply::SuccessReply();
        }
        journalProc.waitForReadyRead(300);
        drainJournal();
    }

    journalProc.waitForReadyRead(300);
    drainJournal();
    const QString remaining = QString::fromUtf8(journalProc.readAll()).trimmed();
    if (!remaining.isEmpty()) {
        fullOutput += remaining + QLatin1Char('\n');
        for (const QString &line : remaining.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            HelperSupport::progressStep(QVariantMap{{QStringLiteral("line"), line.trimmed()}});
        }
    }
    journalProc.terminate();
    journalProc.waitForFinished(1000);

    QProcess stateProc;
    stateProc.start(QStringLiteral("/usr/bin/systemctl"),
                    {QStringLiteral("show"), QStringLiteral("-p"), QStringLiteral("ActiveState"),
                     QStringLiteral("-p"), QStringLiteral("Result"), QStringLiteral("--value"), unitName});
    stateProc.waitForFinished(3000);
    const QStringList stateLines = QString::fromUtf8(stateProc.readAllStandardOutput())
                                       .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    const QString activeState = stateLines.value(0).trimmed();
    const QString result = stateLines.value(1).trimmed();

    if (activeState == QLatin1String("failed") || (!result.isEmpty() && result != QLatin1String("success"))) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(fullOutput.trimmed().isEmpty()
                                      ? QStringLiteral("Falha durante a execução da atualização (%1).").arg(result)
                                      : fullOutput.trimmed());
        return reply;
    }

    QString statusErr;
    QVariantMap payload = collectStatusPayload(&statusErr);
    payload.insert(QStringLiteral("commandOutput"), fullOutput.trimmed());

    ActionReply reply = ActionReply::SuccessReply();
    reply.setData(payload);
    return reply;
}

ActionReply BootcHelper::rollback(const QVariantMap &args)
{
    Q_UNUSED(args);

    HelperSupport::progressStep(QVariantMap{
        {QStringLiteral("line"), QStringLiteral("Agendando reversão para a imagem anterior (bootc rollback)...")}
    });

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(QStringLiteral("/usr/bin/bootc"), {QStringLiteral("rollback")});
    proc.waitForFinished(30000);

    const QString fullOutput = QString::fromUtf8(proc.readAll()).trimmed();
    if (!fullOutput.isEmpty()) {
        HelperSupport::progressStep(QVariantMap{{QStringLiteral("line"), fullOutput}});
    }

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(fullOutput.isEmpty()
                                      ? QStringLiteral("Falha ao executar 'bootc rollback'.")
                                      : fullOutput);
        return reply;
    }

    QString statusErr;
    QVariantMap payload = collectStatusPayload(&statusErr);
    payload.insert(QStringLiteral("commandOutput"), fullOutput);

    ActionReply reply = ActionReply::SuccessReply();
    reply.setData(payload);
    return reply;
}

ActionReply BootcHelper::toggleautotimer(const QVariantMap &args)
{
    const bool enable = args.value(QStringLiteral("enable"), true).toBool();
    const QString subcmd = enable ? QStringLiteral("enable") : QStringLiteral("disable");

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(QStringLiteral("/usr/bin/systemctl"),
               {subcmd, QStringLiteral("--now"), QStringLiteral("bootc-fetch-apply-updates.timer")});
    proc.waitForFinished(15000);

    const QString fullOutput = QString::fromUtf8(proc.readAll()).trimmed();
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        ActionReply reply = ActionReply::HelperErrorReply();
        reply.setErrorDescription(fullOutput.isEmpty()
                                      ? QStringLiteral("Não foi possível alterar o estado do timer bootc-fetch-apply-updates.timer.")
                                      : fullOutput);
        return reply;
    }

    QVariantMap payload;
    payload.insert(QStringLiteral("autoTimerEnabled"), isAutoTimerEnabled());
    payload.insert(QStringLiteral("commandOutput"), fullOutput);

    ActionReply reply = ActionReply::SuccessReply();
    reply.setData(payload);
    return reply;
}

KAUTH_HELPER_MAIN("org.containers.bootc", BootcHelper)
