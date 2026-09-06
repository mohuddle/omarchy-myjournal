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
  property string searchText: ""
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Color.muted
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var listedEntries: {
    var list = Model.filterEntries(service ? service.entries : [], searchText)
    var out = []
    for (var i = list.length - 1; i >= 0; i--) out.push(list[i])
    return out
  }
  readonly property bool currentIsTodo: service && Model.isTodo(service.currentEntry)
  readonly property bool currentIsDone: currentIsTodo && service.currentEntry.done === true
  readonly property string stampLabel: {
    var entry = service ? service.currentEntry : null
    if (!entry) return ""
    var d = new Date(entry.timestamp)
    var when = isNaN(d.getTime()) ? entry.timestamp : Qt.formatDateTime(d, "yyyy-MM-dd HH:mm")
    var kind = Model.isTodo(entry) ? (entry.done ? "Done · " : "ToDo · ") : ""
    return "#" + entry.id + " · " + kind + when
  }

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
      editor.forceActiveFocus()
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
  function switchPanel(direction) { return false }
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
  function newTodo() {
    if (!service) return
    service.startNewTodo()
    syncEditor()
    editor.forceActiveFocus()
  }
  function toggleTodo(id) {
    if (!service) return
    service.toggleDone(id)
  }

  Connections {
    target: root.service
    function onCurrentIdChanged() { root.syncEditor() }
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
        blocked: editor.activeFocus || searchField.activeFocus
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }

        Column {
          anchors.fill: parent
          spacing: Style.space(10)

          Row {
            id: headerRow
            width: parent.width
            spacing: Style.space(10)

            JournalIcon {
              size: Style.space(28)
              foreground: root.accent
              anchors.verticalCenter: parent.verticalCenter
            }
            Column {
              width: parent.width - Style.space(40)
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
                text: root.stampLabel !== "" ? root.stampLabel : "Ready"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            width: parent.width
            height: Math.max(0, parent.height - headerRow.height - parent.spacing)
            spacing: Style.space(12)

            Column {
              width: Style.space(176)
              height: parent.height
              spacing: Style.space(8)

              Item {
                id: toolRow
                width: parent.width
                height: Math.max(newBtn.implicitHeight, todoBtn.implicitHeight, searchField.implicitHeight)

                Button {
                  id: newBtn
                  text: "New"
                  bordered: true
                  foreground: root.foreground
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.newNote()
                }
                Button {
                  id: todoBtn
                  text: "ToDo"
                  bordered: true
                  foreground: root.accent
                  anchors.left: newBtn.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.newTodo()
                }
              }

              ListView {
                id: indexList
                width: parent.width
                height: Math.max(0, parent.height - toolRow.height - parent.spacing)
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root.listedEntries
              delegate: Item {
                required property var modelData
                width: indexList.width
                height: Style.space(44)
                readonly property bool rowTodo: Model.isTodo(modelData)
                readonly property bool rowDone: rowTodo && modelData.done === true
                readonly property bool rowActive: root.service && root.service.currentId === String(modelData.id)
                readonly property color rowColor: rowDone ? root.muted : (rowActive ? root.accent : root.foreground)

                Text {
                  id: mark
                  visible: rowTodo
                  width: visible ? Style.space(28) : 0
                  height: parent.height
                  textFormat: Text.PlainText
                  text: Model.indexMark(modelData).trim()
                  color: rowColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  verticalAlignment: Text.AlignVCenter
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTodo(modelData.id)
                  }
                }
                Text {
                  anchors.left: mark.right
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: rowTodo ? Style.space(2) : Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  anchors.topMargin: Style.space(4)
                  anchors.bottomMargin: Style.space(4)
                  textFormat: Text.PlainText
                  text: "#" + modelData.id + "\n" + Model.previewEntry(modelData, 36)
                  color: rowColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.strikeout: rowDone
                  wrapMode: Text.NoWrap
                  elide: Text.ElideRight
                }
                MouseArea {
                  anchors.left: mark.right
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEntry(modelData.id)
                }
              }
              }

            }

            Column {
              width: Math.max(0, parent.width - Style.space(176) - parent.spacing)
              height: parent.height
              spacing: Style.space(6)

              TextField {
                id: searchField
                width: parent.width
                foreground: root.foreground
                placeholderText: "Search"
                maximumLength: Model.MAX_SEARCH
                text: root.searchText
                onTextChanged: root.searchText = text.length > Model.MAX_SEARCH ? text.substring(0, Model.MAX_SEARCH) : text
              }

              Row {
                id: editorHeader
                width: parent.width
                spacing: Style.space(8)
                Text {
                  id: stampText
                  width: Math.max(0, parent.width - (doneBtn.visible ? doneBtn.width + parent.spacing : 0))
                  textFormat: Text.PlainText
                  text: root.stampLabel
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
                Button {
                  id: doneBtn
                  visible: root.currentIsTodo
                  text: root.currentIsDone ? "Reopen" : "Done"
                  bordered: true
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.toggleDone(root.service.currentId)
                }
              }

              BorderSurface {
                width: parent.width
                height: Math.max(0, parent.height - searchField.height - editorHeader.height - parent.spacing * 2)
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
                    onTextChanged: {
                      if (text.length > Model.MAX_CONTENT)
                        text = text.substring(0, Model.MAX_CONTENT)
                      if (activeFocus && root.service) root.service.setContent(text)
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
