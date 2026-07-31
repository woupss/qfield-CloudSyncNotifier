import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qfield
import Theme

//============================================
//     CloudSync (App-Wide Plugin)
//============================================
Item {
    id: cloudSync
    objectName: "CloudSync"

//============     TRADUCTION   ===============

    readonly property string locale: Qt.locale().name.substring(0, 2) === "fr" ? "fr" : "en"

    readonly property var dictionnaireAnglais: {
        "Mise à jour disponible": "Update available",
        "Une nouvelle version de ce projet est disponible sur QFieldCloud. Voulez-vous synchroniser maintenant ?": "A new version of this project is available on QFieldCloud. Do you want to sync now?",
        "Synchroniser maintenant": "Sync now",
        "Plus tard": "Later",

        "Connexion à QFieldCloud": "QFieldCloud login",
        "Un mot de passe est nécessaire pour lancer la synchronisation.": "A password is needed to start synchronization.",
        "Mot de passe": "Password",
        "Identifiant QFieldCloud": "QFieldCloud username",
        "🔑 Se connecter": "🔑 Log in",
        "Annuler": "Cancel",
        "Connexion en cours...": "Logging in...",
        "❌ Mot de passe requis.": "❌ Password required.",
        "❌ Identifiant QFieldCloud introuvable. Saisissez-le ci-dessus.": "❌ QFieldCloud username not found. Enter it above.",
        "❌ Réponse inattendue du serveur (pas de token).": "❌ Unexpected server response (no token).",
        "❌ Erreur de connexion : réponse illisible.": "❌ Connection error: unreadable response.",
        "❌ Echec de connexion (": "❌ Login failed (",
        ") : identifiant ou mot de passe incorrect ?": "): incorrect username or password?",
        "❌ Impossible de joindre le serveur. Vérifiez votre connexion internet.": "❌ Cannot reach the server. Check your internet connection.",
        "⚠️ Session expirée. Veuillez vous reconnecter.": "⚠️ Session expired. Please log in again.",
        "❌ Impossible de vérifier votre session : pas de connexion au serveur.": "❌ Cannot verify your session: no connection to the server.",
        "⏱️ La synchronisation a expiré. Vérifiez votre connexion et réessayez.": "⏱️ Synchronization timed out. Check your connection and try again.",
        "🔼 Masquer": "🔼 Hide",
        "🔽 Voir utilisateur / serveur": "🔼 Show user / server",
        "Serveur : ": "Server: ",
        "Utilisateur : ": "User: ",
        "(modifier)": "(edit)",
        "☁️ Officiel": "☁️ Official",
        "🏠 Auto-hébergé": "🏠 Self-hosted",

        "OK": "OK",
        "Aucune synchronisation en attente": "No sync pending",

        "Synchronisation en cours...": "Synchronization in progress...",
        "Le téléchargement est en cours.\nLe projet va se recharger automatiquement.": "Download in progress.\nThe project will reload automatically."
    }

    function tr(texteFrancais) {
        if (locale === "fr") return texteFrancais;
        return dictionnaireAnglais[texteFrancais] || texteFrancais;
    }

//============   FIN TRADUCTION   ===============

    property var mainWindow: iface ? iface.mainWindow() : null

    // ============================================
    //   STOCKAGE PERSISTANT
    // ============================================

    Settings {
        id: syncPersist
        category: "CloudSyncNotifier"
        property bool wasInProgress: false
        property string popupName: ""
    }

    Settings {
        id: credsPersist
        category: "CloudSyncCreds"
        property string cloudServer: "https://app.qfield.cloud/api/v1"
        property string serverMode: "official"
        property string selfHostedServerUrl: ""
        property string officialToken: ""
        property string officialUsername: ""
        property string selfHostedToken: ""
        property string selfHostedUsername: ""
        property string projectServerMap: "{}"
    }

    readonly property string officialServerUrl: "https://app.qfield.cloud"
    readonly property bool needsLogin: getEffectiveToken() === ""

    function getEffectiveToken() {
        return credsPersist.serverMode === "official" ? credsPersist.officialToken : credsPersist.selfHostedToken;
    }
    function setEffectiveToken(tok) {
        if (credsPersist.serverMode === "official") credsPersist.officialToken = tok;
        else credsPersist.selfHostedToken = tok;
    }
    function getEffectiveUsername() {
        return credsPersist.serverMode === "official" ? credsPersist.officialUsername : credsPersist.selfHostedUsername;
    }
    function setEffectiveUsername(usr) {
        if (credsPersist.serverMode === "official") credsPersist.officialUsername = usr;
        else credsPersist.selfHostedUsername = usr;
    }

    function normalizeApiUrl(url) {
        var u = (url || "").replace(/\/+$/, "");
        if (u.indexOf("/api/v1") === -1) u = u + "/api/v1";
        return u;
    }

    function getKnownServerForProject(uuid) {
        try {
            var map = JSON.parse(credsPersist.projectServerMap || "{}");
            return map[uuid] || null;
        } catch (e) { return null; }
    }
    function rememberServerForProject(uuid, value) {
        try {
            var map = JSON.parse(credsPersist.projectServerMap || "{}");
            map[uuid] = value;
            credsPersist.projectServerMap = JSON.stringify(map);
        } catch (e) {}
    }

    function normalizeLocalPath(p) {
        if (p.indexOf("file:///") === 0) p = p.substring(7);
        else if (p.indexOf("file://") === 0) p = "/" + p.substring(7);
        if (p.endsWith("/")) p = p.substring(0, p.length - 1);
        return p;
    }

    function looksLikeCloudProjectPath(p) {
        var pl = p.toLowerCase();
        return pl.indexOf("/cloud_projects/") !== -1 || pl.indexOf("/cloudprojects/") !== -1;
    }

    function getProjectRootPath() {
        if (typeof qgisProject === "undefined" || !qgisProject) return "";

        var candidate = qgisProject.homePath ? normalizeLocalPath(qgisProject.homePath.toString()) : "";
        if (!looksLikeCloudProjectPath(candidate) && qgisProject.fileName) {
            var filePath = normalizeLocalPath(qgisProject.fileName.toString());
            var lastSlash = filePath.lastIndexOf("/");
            var derived = lastSlash > 0 ? filePath.substring(0, lastSlash) : "";
            if (looksLikeCloudProjectPath(derived)) return derived;
        }
        return candidate;
    }

    function getCloudProjectInfo() {
        var path = getProjectRootPath();
        var pathLower = path.toLowerCase();
        var marker = "";
        if (pathLower.indexOf("/cloudprojects/") !== -1) marker = "/cloudprojects/";
        else if (pathLower.indexOf("/cloud_projects/") !== -1) marker = "/cloud_projects/";
        if (marker === "") return { error: true, debugMsg: path };
        var sub = path.substring(pathLower.indexOf(marker) + marker.length);
        var parts = sub.split("/");
        if (parts.length < 2) return { error: true, debugMsg: sub };
        return { error: false, owner: parts[0], uuid: parts[1] };
    }

    function isCloudProjectOpen() {
        return !getCloudProjectInfo().error;
    }

    function resolveKnownServerForProject(cloudInfo) {
        if (!cloudInfo || cloudInfo.error) return;
        var known = getKnownServerForProject(cloudInfo.uuid);
        if (!known) return;
        if (known === "official") {
            credsPersist.serverMode = "official";
            credsPersist.cloudServer = normalizeApiUrl(officialServerUrl);
        } else {
            credsPersist.serverMode = "selfhosted";
            credsPersist.selfHostedServerUrl = known;
            credsPersist.cloudServer = normalizeApiUrl(known);
        }
    }

    property var _qfCloudConnectionCandidates: ["cloudConnection", "qfieldCloudConnection", "QFieldCloudConnection", "connection"]

    function getQFieldCloudConnection() {
        for (var i = 0; i < _qfCloudConnectionCandidates.length; i++) {
            var obj = iface.findItemByObjectName(_qfCloudConnectionCandidates[i]);
            if (obj && (obj.hasToken !== undefined || obj.token !== undefined)) return obj;
        }
        return null;
    }

    function importServerAndUsernameFromQField() {
        var conn = getQFieldCloudConnection();
        if (!conn) return;
        var connUrl = (conn.url || "").replace(/\/+$/, "");
        if (connUrl) {
            var isOfficial = connUrl.indexOf("app.qfield.cloud") !== -1;
            credsPersist.serverMode = isOfficial ? "official" : "selfhosted";
            if (isOfficial) {
                credsPersist.cloudServer = normalizeApiUrl(officialServerUrl);
            } else {
                credsPersist.selfHostedServerUrl = connUrl;
                credsPersist.cloudServer = normalizeApiUrl(connUrl);
            }
        }
        if (conn.username) setEffectiveUsername(conn.username);
    }

    function performLogin(username, password, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", credsPersist.cloudServer + "/auth/login/");
        xhr.timeout = 15000;
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0) {
                    callback(false, tr("❌ Impossible de joindre le serveur. Vérifiez votre connexion internet."));
                    return;
                }
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        var resp = JSON.parse(xhr.responseText);
                        if (resp.token) {
                            setEffectiveToken(resp.token);
                            setEffectiveUsername(username);
                            var cloudInfoNow = getCloudProjectInfo();
                            if (!cloudInfoNow.error) {
                                var val = credsPersist.serverMode === "official" ? "official" : credsPersist.selfHostedServerUrl;
                                rememberServerForProject(cloudInfoNow.uuid, val);
                            }
                            callback(true, "");
                        } else {
                            callback(false, tr("❌ Réponse inattendue du serveur (pas de token)."));
                        }
                    } catch (e_parse) {
                        callback(false, tr("❌ Erreur de connexion : réponse illisible."));
                    }
                } else {
                    callback(false, tr("❌ Echec de connexion (") + xhr.status + tr(") : identifiant ou mot de passe incorrect ?"));
                }
            }
        };
        xhr.ontimeout = function() {
            callback(false, tr("❌ Impossible de joindre le serveur. Vérifiez votre connexion internet."));
        };
        xhr.onerror = function() {
            callback(false, tr("❌ Impossible de joindre le serveur. Vérifiez votre connexion internet."));
        };
        xhr.send("username=" + encodeURIComponent(username) + "&password=" + encodeURIComponent(password));
    }

    // ============================================
    //   VÉRIFICATION DE VALIDITÉ DU TOKEN
    // ============================================

    // NOTE: adapte l'en-tête "Authorization" ci-dessous si CloudSync.qml
    // (appels REST orphelins) utilise un format différent sur ton instance.
    function verifyTokenValid(callback) {
        var token = getEffectiveToken();
        if (!token) { callback("no_token"); return; }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", credsPersist.cloudServer + "/projects/");
        xhr.timeout = 10000;
        xhr.setRequestHeader("Authorization", "Token " + token);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0) { callback("network_error"); return; }
                if (xhr.status === 401 || xhr.status === 403) { callback("invalid_token"); return; }
                if (xhr.status >= 200 && xhr.status < 300) { callback("ok"); return; }
                // Statut inattendu (5xx, etc.) : on ne bloque pas, on laisse QField gérer la sync
                callback("ok");
            }
        };
        xhr.ontimeout = function() { callback("network_error"); };
        xhr.onerror = function() { callback("network_error"); };
        xhr.send();
    }

    property var _pendingContinuation: null

    function ensureAuthenticated(onReady) {
        if (needsLogin) importServerAndUsernameFromQField();
        if (!needsLogin) { onReady(); return; }
        _pendingContinuation = onReady;
        loginErrorLabel.text = "";
        loginPasswordField.text = "";
        _showPassword = false;
        loginDialog.open();
    }

    property bool _loginBusy: false
    property bool _showServerOverride: false
    property bool _showPassword: false

    function attemptLogin() {
        var username = getEffectiveUsername();
        var password = loginPasswordField.text;
        if (!username && loginUsernameField.text) username = loginUsernameField.text;
        if (!username) {
            loginErrorLabel.text = tr("❌ Identifiant QFieldCloud introuvable. Saisissez-le ci-dessus.");
            return;
        }
        if (!password) {
            loginErrorLabel.text = tr("❌ Mot de passe requis.");
            return;
        }
        setEffectiveUsername(username);
        loginErrorLabel.text = "";
        _loginBusy = true;
        performLogin(username, password, function(ok, err) {
            _loginBusy = false;
            if (ok) {
                loginPasswordField.text = "";
                loginDialog.close();
                var cb = _pendingContinuation;
                _pendingContinuation = null;
                if (cb) cb();
            } else {
                loginErrorLabel.text = err;
            }
        });
    }

    // ============================================
    //   BARRE D'OUTILS : DRAWER
    // ============================================

    Component.onCompleted: {
        if (syncPersist.wasInProgress) {
            syncPersist.wasInProgress = false
            let savedName = syncPersist.popupName
            syncPersist.popupName = ""
            _syncBusy = false
            closePopupTimer.popupName = savedName
            closePopupTimer.restart()
        }
        iface.addItemToPluginsToolbar(syncDrawer)
        updateSyncPendingState()
    }

    QfToolButton {
        id: syncDrawer
        iconSource: "CldSync.svg"
        bgcolor: Theme.darkGray
        visible: _syncPending
        round: true
        onClicked: {
            let cloudBtn = iface.findItemByObjectName("cloudButton") || iface.findItemByObjectName("CloudButton")
            if (!cloudBtn || cloudBtn.showSync !== true) {
                noPendingSyncDialog.open();
                return;
            }
            syncAvailableDialog.open();
        }
    }

    // ============================================
    //   DÉTECTION ET SUIVI DE SYNC
    // ============================================

    property bool _syncInProgress: false
    property bool _syncBusy: false
    property bool _syncPending: false

    function updateSyncPendingState() {
        if (!isCloudProjectOpen()) { _syncPending = false; return }
        let cloudBtn = iface.findItemByObjectName("cloudButton") || iface.findItemByObjectName("CloudButton")
        _syncPending = !!(cloudBtn && cloudBtn.showSync === true)
    }

    Timer {
        id: syncPendingPoller
        interval: 3000
        repeat: true
        running: true
        onTriggered: updateSyncPendingState()
    }

    Timer {
        id: progressWatcher
        interval: 400
        repeat: true
        running: _syncBusy
        onTriggered: {
            let p = iface.findItemByObjectName(syncPersist.popupName)
            let cloudBtn = iface.findItemByObjectName("cloudButton") || iface.findItemByObjectName("CloudButton")
            if (p) {
                if (p.progress !== undefined && p.progress > 0.95) { finishSyncAction(); return }
                let progressBar = iface.findItemByObjectName("progressBar") || iface.findItemByObjectName("syncProgressBar")
                if (progressBar && progressBar.value > 0.95) { finishSyncAction(); return }
            }
            if (cloudBtn && cloudBtn.showSync === false) finishSyncAction()
        }
    }

    Timer {
        id: syncWatchdog
        interval: 45000
        repeat: false
        running: _syncBusy
        onTriggered: {
            finishSyncAction()
            verifyTokenValid(function(result) {
                if (result === "invalid_token" || result === "no_token") {
                    setEffectiveToken("")
                    showSyncError(tr("⚠️ Session expirée. Veuillez vous reconnecter."))
                } else {
                    showSyncError(tr("⏱️ La synchronisation a expiré. Vérifiez votre connexion et réessayez."))
                }
            })
        }
    }

    function finishSyncAction() {
        _syncBusy = false
        if (syncProgressDialog.opened) syncProgressDialog.close()
        progressWatcher.stop()
        updateSyncPendingState()
    }

    function isMainMapScreenVisible() {
        var welcomeScreen = iface.findItemByObjectName("welcomeScreen");
        if (welcomeScreen && welcomeScreen.visible) return false;
        var qfieldSettings = iface.findItemByObjectName("qfieldSettings");
        if (qfieldSettings && qfieldSettings.visible) return false;
        var dashBoard = iface.findItemByObjectName("dashBoard");
        if (dashBoard && dashBoard.opened) return false;
        var aboutDialog = iface.findItemByObjectName("aboutDialog");
        if (aboutDialog && aboutDialog.visible) return false;
        var qfieldLocalDataPickerScreen = iface.findItemByObjectName("qfieldLocalDataPickerScreen");
        if (qfieldLocalDataPickerScreen && qfieldLocalDataPickerScreen.visible) return false;
        return true;
    }

    function checkSyncNeeded() {
        if (_syncInProgress || _syncBusy) return
        if (syncAvailableDialog.opened || loginDialog.opened || syncProgressDialog.opened) return
        if (!isMainMapScreenVisible()) return
        var cloudInfo = getCloudProjectInfo();
        if (cloudInfo.error) return
        let cloudBtn = iface.findItemByObjectName("cloudButton") || iface.findItemByObjectName("CloudButton")
        if (!cloudBtn) return
        if (cloudBtn.showSync === true) syncAvailableDialog.open()
        updateSyncPendingState()
    }

    Timer { id: startupTimer; interval: 2500; repeat: false; running: false; onTriggered: checkSyncNeeded() }
  //  Timer { id: pollTimer; interval: 60000; repeat: true; running: true; onTriggered: { if (!_syncBusy) checkSyncNeeded() } }

    Connections {
        target: iface
        function onLoadProjectStarted() { finishSyncAction() }
        function onLoadProjectEnded(path, name) {
            finishSyncAction()
            if (_syncInProgress) {
                closeCloudPopup(syncPersist.popupName)
                _syncInProgress = false
                syncPersist.wasInProgress = false
            } else {
                startupTimer.restart()
            }
            updateSyncPendingState()
        }
    }

    // ============================================
    //   PIPELINE DE SYNCHRONISATION
    // ============================================

    function startSyncFlow() {
        syncAvailableDialog.close();
        var cloudInfo = getCloudProjectInfo();
        if (cloudInfo.error) { beginNativeSync(); return; }
        resolveKnownServerForProject(cloudInfo);
        ensureAuthenticated(function() {
            verifyTokenValid(function(result) {
                if (result === "ok") {
                    beginNativeSync();
                } else if (result === "invalid_token" || result === "no_token") {
                    setEffectiveToken("");
                    showSyncError(tr("⚠️ Session expirée. Veuillez vous reconnecter."));
                    ensureAuthenticated(function() { beginNativeSync(); });
                } else {
                    showSyncError(tr("❌ Impossible de vérifier votre session : pas de connexion au serveur."));
                }
            });
        });
    }

    function showSyncError(msg) {
        syncErrorDialog.message = msg;
        syncErrorDialog.open();
    }

    // ============================================
    //   DÉCLENCHEMENT DE LA SYNCHRONISATION NATIVE
    // ============================================

    function beginNativeSync() {
        _syncBusy = true;
        syncProgressDialog.open();
        triggerSync();
    }

    function triggerSync() {
        _syncInProgress = true
        syncPersist.wasInProgress = true
        let candidates = ["qfieldCloudPopup", "QFieldCloudPopup", "cloudPopup",
                          "qfieldCloudScreen", "QFieldCloudScreen", "cloudScreen",
                          "cloudProjectPage", "QFieldCloudProjectPage"]
        let found = false
        for (let name of candidates) {
            let popup = iface.findItemByObjectName(name)
            if (popup) {
                if (typeof popup.show === "function") popup.show()
                else popup.visible = true
                syncPersist.popupName = name
                syncTriggerTimer.popupName = name
                syncTriggerTimer.restart()
                found = true
                break
            }
        }
        if (!found) {
            let cloudBtn = iface.findItemByObjectName("cloudButton") || iface.findItemByObjectName("CloudButton")
            if (cloudBtn && typeof cloudBtn.clicked === "function") cloudBtn.clicked()
        }
    }

    function closeCloudPopup(popupName) {
        if (!popupName) return
        let p = iface.findItemByObjectName(popupName)
        if (p) {
            if (typeof p.close === "function") p.close()
            else p.visible = false
        }
    }

    Timer {
        id: syncTriggerTimer
        interval: 100
        repeat: false
        running: false
        property string popupName: ""
        onTriggered: {
            let p = iface.findItemByObjectName(popupName)
            if (p && typeof p.projectPush === "function") {
                p.projectPush(true)
                autoCloseMapTimer.popupName = popupName
                autoCloseMapTimer.restart()
            }
        }
    }
    Timer { id: autoCloseMapTimer; interval: 1; repeat: false; running: false; property string popupName: ""; onTriggered: closeCloudPopup(popupName) }
    Timer { id: closePopupTimer; interval: 1; repeat: false; running: false; property string popupName: ""; onTriggered: closeCloudPopup(popupName) }

    // ============================================
    //   DIALOGUES
    // ============================================

    // --- 1) Sync disponible ---
    Dialog {
        id: syncAvailableDialog
        parent: mainWindow ? mainWindow.contentItem : null
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        padding: 24
        width: mainWindow ? Math.min(mainWindow.width * 0.90, 400) : 300
        background: Rectangle { radius: 16; color: "#FFFFFF"; border.color: "#4A6FAE"; border.width: 3  }
        contentItem: ColumnLayout {
            spacing: 20
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 56; height: 56; radius: 28; color: "#4A6FAE"
                Label { anchors.centerIn: parent; text: "☁"; font.pixelSize: 30; color: "white" }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                text: tr("Mise à jour disponible")
                font.pixelSize: 20; font.bold: true; color: "#4A6FAE"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: tr("Une nouvelle version de ce projet est disponible sur QFieldCloud. Voulez-vous synchroniser maintenant ?")
                font.pixelSize: 14; color: "#666666"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                Button {
                    Layout.fillWidth: true; text: tr("Synchroniser maintenant")
                    font.pixelSize: 15; font.bold: true
                    background: Rectangle { radius: 10; color: parent.pressed ? "#3B598C" : "#4A6FAE" }
                    contentItem: Text { text: parent.text; font: parent.font; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: startSyncFlow()
                }
                Button {
                    Layout.fillWidth: true; text: tr("Plus tard")
                    font.pixelSize: 15
                    background: Rectangle { radius: 10; color: parent.pressed ? Qt.rgba(0,0,0,0.08) : Qt.rgba(0,0,0,0.04); border.color: Qt.rgba(0,0,0,0.12); border.width: 1 }
                    contentItem: Text { text: parent.text; font: parent.font; color: "#000000"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: syncAvailableDialog.close()
                }
            }
        }
    }

    // --- 2) Connexion ---
    Dialog {
        id: loginDialog
        parent: mainWindow ? mainWindow.contentItem : null
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnEscape
        padding: 24
        width: mainWindow ? Math.min(mainWindow.width * 0.90, 400) : 300
        background: Rectangle { radius: 16; color: "#FFFFFF"; border.color: "#4A6FAE"; border.width: 3 }
        onClosed: { if (_pendingContinuation) _pendingContinuation = null; }
        contentItem: ColumnLayout {
            spacing: 14
            Label {
                Layout.fillWidth: true
                text: tr("Connexion à QFieldCloud")
                font.pixelSize: 20; font.bold: true; color: "#4A6FAE"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: tr("Un mot de passe est nécessaire pour lancer la synchronisation.")
                font.pixelSize: 13; color: "#666666"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            BusyIndicator { Layout.alignment: Qt.AlignHCenter; visible: _loginBusy; running: _loginBusy }
            Label {
                Layout.fillWidth: true
                visible: _loginBusy
                text: tr("Connexion en cours...")
                font.pixelSize: 13; color: "#666666"; horizontalAlignment: Text.AlignHCenter
            }
            Label {
                Layout.fillWidth: true
                visible: !_loginBusy
                text: tr("Serveur : ") + credsPersist.cloudServer + " (" + credsPersist.serverMode + ")"
                font.pixelSize: 11; color: "#888888"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
            }
            Label {
                Layout.fillWidth: true
                visible: !_loginBusy
                text: tr("Utilisateur : ") + (getEffectiveUsername() || "(vide)")
                font.pixelSize: 11; color: "#888888"
                horizontalAlignment: Text.AlignHCenter
            }
            TextField {
                id: loginUsernameField
                Layout.fillWidth: true
                visible: getEffectiveUsername() === ""
                placeholderText: tr("Identifiant QFieldCloud")
                font.pixelSize: 13
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !_loginBusy
                spacing: 6
                TextField {
                    id: loginPasswordField
                    Layout.fillWidth: true
                    placeholderText: tr("Mot de passe")
                    echoMode: _showPassword ? TextInput.Normal : TextInput.Password
                    font.pixelSize: 13
                    onAccepted: attemptLogin()
                }
                Text {
                    text: _showPassword ? "🔒" : "👁"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: _showPassword = !_showPassword }
                }
            }
            Label {
                id: loginErrorLabel
                Layout.fillWidth: true
                font.pixelSize: 12; color: "#B00020"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: false
                text: _showServerOverride ? tr("🔼 Masquer") : (tr("Serveur : ") + credsPersist.cloudServer + " " + tr("(modifier)"))
                font.pixelSize: 10; color: "#999999"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
                MouseArea { anchors.fill: parent; onClicked: _showServerOverride = !_showServerOverride }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                visible: false
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Button {
                        text: tr("☁️ Officiel")
                        Layout.fillWidth: true
                        enabled: false
                        opacity: 0.5
                        background: Rectangle { radius: 8; color: credsPersist.serverMode === "official" ? "#4A6FAE" : "#ddd" }
                        contentItem: Text { text: parent.text; color: credsPersist.serverMode === "official" ? "white" : "#333"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11 }
                        onClicked: { credsPersist.serverMode = "official"; credsPersist.cloudServer = normalizeApiUrl(officialServerUrl); }
                    }
                    Button {
                        text: tr("🏠 Auto-hébergé")
                        Layout.fillWidth: true
                        enabled: false
                        opacity: 0.5
                        background: Rectangle { radius: 8; color: credsPersist.serverMode === "selfhosted" ? "#4A6FAE" : "#ddd" }
                        contentItem: Text { text: parent.text; color: credsPersist.serverMode === "selfhosted" ? "white" : "#333"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11 }
                        onClicked: { credsPersist.serverMode = "selfhosted"; credsPersist.cloudServer = normalizeApiUrl(credsPersist.selfHostedServerUrl); }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    visible: credsPersist.serverMode === "selfhosted"
                    enabled: false
                    placeholderText: "https://mon-serveur.exemple.com"
                    text: credsPersist.selfHostedServerUrl
                    font.pixelSize: 12
                    onTextChanged: { credsPersist.selfHostedServerUrl = text; credsPersist.cloudServer = normalizeApiUrl(text); }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8; visible: !_loginBusy
                Button {
                    Layout.fillWidth: true
                    text: tr("🔑 Se connecter")
                    background: Rectangle { radius: 10; color: "#4A6FAE" }
                    contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13 }
                    onClicked: attemptLogin()
                }
                Button {
                    Layout.fillWidth: true
                    text: tr("Annuler")
                    background: Rectangle { radius: 10; color: "#ccc" }
                    contentItem: Text { text: parent.text; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13 }
                    onClicked: { _pendingContinuation = null; loginDialog.close(); }
                }
            }
        }
    }

    Dialog {
        id: syncErrorDialog
        property string message: ""
        parent: mainWindow ? mainWindow.contentItem : null
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        padding: 24
        width: mainWindow ? Math.min(mainWindow.width * 0.90, 380) : 300
        background: Rectangle { radius: 16; color: "#FFFFFF"; border.color: "#B00020"; border.width: 3 }
        contentItem: ColumnLayout {
            spacing: 16
            Label {
                Layout.fillWidth: true
                text: syncErrorDialog.message
                font.pixelSize: 15; font.bold: true; color: "#B00020"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Button {
                Layout.fillWidth: true
                text: tr("OK")
                background: Rectangle { radius: 10; color: "#B00020" }
                contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13 }
                onClicked: syncErrorDialog.close()
            }
        }
    }

    Dialog {
        id: noPendingSyncDialog
        parent: mainWindow ? mainWindow.contentItem : null
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        padding: 24
        width: mainWindow ? Math.min(mainWindow.width * 0.90, 380) : 300
        background: Rectangle { radius: 16; color: "#FFFFFF"; border.color: "#4A6FAE"; border.width: 3 }
        contentItem: ColumnLayout {
            spacing: 16
            Label {
                Layout.fillWidth: true
                text: tr("Aucune synchronisation en attente")
                font.pixelSize: 16; font.bold: true; color: "#4A6FAE"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Button {
                Layout.fillWidth: true
                text: tr("OK")
                background: Rectangle { radius: 10; color: "#4A6FAE" }
                contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13 }
                onClicked: noPendingSyncDialog.close()
            }
        }
    }

    // --- 3) Progression de la synchronisation native ---
    Dialog {
        id: syncProgressDialog
        parent: mainWindow ? mainWindow.contentItem : null
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.NoAutoClose
        padding: 24
        onClosed: _syncBusy = false
        width: mainWindow ? Math.min(mainWindow.width * 0.90, 400) : 300
        background: Rectangle { radius: 16; color: "#FFFFFF"; border.color: "#4A6FAE"; border.width: 3 }
        contentItem: ColumnLayout {
            spacing: 20
            BusyIndicator {
                id: busyIndicator; Layout.alignment: Qt.AlignHCenter; running: _syncBusy
                implicitWidth: 56; implicitHeight: 56
                contentItem: Item {
                    Canvas {
                        id: canvas; anchors.fill: parent; antialiasing: true; property real arcSpan: 0.2
                        SequentialAnimation on arcSpan {
                            loops: Animation.Infinite; running: busyIndicator.running
                            NumberAnimation { from: 0.2; to: 1.6; duration: 1000; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1.6; to: 0.2; duration: 1000; easing.type: Easing.InOutSine }
                        }
                        RotationAnimation on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: busyIndicator.running }
                        onArcSpanChanged: canvas.requestPaint()
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset(); ctx.strokeStyle = "#4A6FAE"; ctx.lineWidth = 4; ctx.lineCap = "round";
                            ctx.beginPath(); ctx.arc(width/2, height/2, width/2 - ctx.lineWidth, 0, Math.PI * canvas.arcSpan); ctx.stroke();
                        }
                    }
                }
            }
            Label {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                text: tr("Synchronisation en cours...")
                font.pixelSize: 20; font.bold: true; color: "#4A6FAE"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: tr("Le téléchargement est en cours.\nLe projet va se recharger automatiquement.")
                font.pixelSize: 14; color: "#666666"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
        }
    }
}
