import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.mohuddle.myjournal"
  ipcTarget: "io.github.mohuddle.myjournal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool showingSettings: false
  property string searchText: ""
  property string passDraft: ""
  property string passConfirm: ""
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Color.muted
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool locked: service ? service.locked : false
  readonly property var listedEntries: {
    var list = Model.filterEntries(service ? service.entries : [], searchText)
    var out = []
    for (var i = list.length - 1; i >= 0; i--) out.push(list[i])
    return out
  }
  readonly property string stampLabel: {
    var entry = service ? service.currentEntry : null
    if (!entry) return ""
    var d = new Date(entry.timestamp)
    if (isNaN(d.getTime())) return "#" + entry.id + " · " + entry.timestamp
    return "#" + entry.id + " · " + Qt.formatDateTime(d, "yyyy-MM-dd HH:mm")
  }

  // Pinned overlay: stay visible across windows and workspaces. Other bar
  // widgets must not close this via the popout coordinator.
  function closeForPopoutSwitch() {}

  readonly property int pinTopMargin: {
    if (root.bar && root.bar.position === "top")
      return (root.bar.barSize || Style.bar.sizeHorizontal) + Style.gapsOut
    return Style.gapsOut
  }
  readonly property int pinRightMargin: {
    if (root.bar && root.bar.position === "right")
      return (root.bar.barSize || Style.bar.sizeHorizontal) + Style.gapsOut
    return Style.gapsOut
  }

  function open() {
    controller.show()
    if (service) service.begin()
    Qt.callLater(function() {
      root.syncEditor()
      if (root.locked) passField.forceActiveFocus()
      else editor.forceActiveFocus()
    })
  }
  function close() {
    if (service) {
      service.flushBlank()
      service.saveNow()
    }
    controller.hide()
  }
  function toggle() { if (opened) close(); else open() }
  function switchPanel(direction) {
    return false
  }
  function syncEditor() {
    var next = service ? service.currentContent() : ""
    if (editor.text !== next) editor.text = next
  }
  function openEntry(id) {
    if (!service) return
    service.openEntry(id)
    syncEditor()
    editor.forceActiveFocus()
  }
  function newNote() {
    if (!service) return
    service.startNewNote()
    syncEditor()
    editor.forceActiveFocus()
  }

  Connections {
    target: root.service
    function onCurrentIdChanged() { root.syncEditor() }
    function onUnlockedChanged() {
      if (root.service && root.service.unlocked) {
        root.syncEditor()
        editor.forceActiveFocus()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    implicitWidth: Style.space(560)
    implicitHeight: Style.space(440)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    WlrLayershell.namespace: "myjournal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors.top: true
    anchors.right: true
    margins.top: root.pinTopMargin
    margins.right: root.pinRightMargin

    BorderSurface {
      id: card
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: Style.spacing.popupPadding

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      blocked: editor.activeFocus || searchField.activeFocus || passField.activeFocus || confirmField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(10)

          JournalIcon {
            size: Style.space(28)
            foreground: root.accent
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            width: parent.width - Style.space(80)
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: "My Journal"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: root.locked ? "Enter passphrase to unlock" : (root.showingSettings ? "Encryption" : (root.stampLabel !== "" ? root.stampLabel : "Ready"))
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Button {
            visible: !root.locked
            width: Style.space(32)
            implicitHeight: Style.space(32)
            horizontalPadding: 0
            verticalPadding: 0
            iconText: ""
            selected: root.showingSettings
            bordered: true
            foreground: root.foreground
            tooltipText: "Settings"
            onClicked: root.showingSettings = !root.showingSettings
          }
        }

        Column {
          visible: root.locked
          width: parent.width
          spacing: Style.space(8)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "This journal is encrypted with age. The passphrase stays in memory only while the shell session is unlocked."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          TextField {
            id: passField
            width: parent.width
            foreground: root.foreground
            password: true
            placeholderText: "Passphrase"
            text: root.passDraft
            onTextChanged: root.passDraft = text
            Keys.onReturnPressed: if (root.service) root.service.unlock(root.passDraft)
            Keys.onEnterPressed: if (root.service) root.service.unlock(root.passDraft)
          }
          Button {
            width: parent.width
            text: "Unlock"
            bordered: true
            foreground: root.foreground
            onClicked: if (root.service) root.service.unlock(root.passDraft)
          }
          Text {
            visible: root.service && root.service.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.service ? root.service.lastError : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: !root.locked && root.showingSettings
          width: parent.width
          spacing: Style.space(8)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.service && root.service.encryptedOnDisk
              ? "The journal is stored as journal.json.age. Locking clears the passphrase from memory."
              : "Autosave writes journal.json and a readable notes.txt. Set a passphrase to encrypt the whole JSON file with age and remove the plaintext copies."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          TextField {
            visible: !(root.service && root.service.encryptedOnDisk)
            width: parent.width
            foreground: root.foreground
            password: true
            placeholderText: "New passphrase"
            text: root.passDraft
            onTextChanged: root.passDraft = text
          }
          TextField {
            id: confirmField
            visible: !(root.service && root.service.encryptedOnDisk)
            width: parent.width
            foreground: root.foreground
            password: true
            placeholderText: "Confirm passphrase"
            text: root.passConfirm
            onTextChanged: root.passConfirm = text
          }
          Button {
            visible: !(root.service && root.service.encryptedOnDisk)
            width: parent.width
            text: "Encrypt journal with age"
            bordered: true
            foreground: root.foreground
            onClicked: if (root.service) root.service.enableEncryption(root.passDraft, root.passConfirm)
          }
          Button {
            visible: root.service && root.service.encryptedOnDisk
            width: parent.width
            text: "Lock journal"
            bordered: true
            foreground: root.foreground
            onClicked: {
              if (root.service) root.service.lock()
              root.showingSettings = false
              root.passDraft = ""
              root.passConfirm = ""
            }
          }
          Text {
            visible: root.service && root.service.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.service ? root.service.lastError : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: !root.locked && !root.showingSettings
          width: parent.width
          height: parent.height - Style.space(86)
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)
            Button {
              text: "New"
              bordered: true
              foreground: root.foreground
              onClicked: root.newNote()
            }
            TextField {
              id: searchField
              width: parent.width - Style.space(88)
              foreground: root.foreground
              placeholderText: "Search notes"
              text: root.searchText
              onTextChanged: root.searchText = text
            }
          }

          Row {
            width: parent.width
            height: parent.height - Style.space(42)
            spacing: Style.space(12)

            ListView {
              id: indexList
              width: Style.space(168)
              height: parent.height
              clip: true
              spacing: Style.space(2)
              boundsBehavior: Flickable.StopAtBounds
              model: root.listedEntries
              delegate: Item {
                required property var modelData
                width: indexList.width
                height: Style.space(44)
                Text {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  textFormat: Text.PlainText
                  text: "#" + modelData.id + "\n" + Model.preview(modelData.content, 42)
                  color: root.service && root.service.currentId === String(modelData.id) ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.NoWrap
                  elide: Text.ElideRight
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEntry(modelData.id)
                }
              }
            }

            Column {
              width: Math.max(0, parent.width - indexList.width - parent.spacing)
              height: parent.height
              spacing: Style.space(6)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.stampLabel
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              BorderSurface {
                width: parent.width
                height: parent.height - Style.space(22)
                color: "transparent"
                borderSpec: Border.controlSpec(editor.activeFocus ? "focus" : "normal", root.foreground, root.accent)
                radius: Style.cornerRadius

                Flickable {
                  id: editorFlick
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  contentWidth: width
                  contentHeight: editor.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds

                  TextEdit {
                    id: editor
                    width: editorFlick.width
                    wrapMode: TextEdit.Wrap
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    selectedTextColor: root.foreground
                    selectionColor: Style.selectionFillFor(root.foreground, root.accent)
                    textFormat: TextEdit.PlainText
                    onTextChanged: if (activeFocus && root.service) root.service.setContent(text)
                  }
                }
              }
            }
          }
        }
      }
    }
    }
  }
}
