import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The post-it drawer. Each saved note is appended to a Markdown file under a
// timestamp heading, so the whole log opens as one document in Omawrite.
// Unsaved text stays in the drawer between opens.
Panel {
  id: root
  moduleName: "afrancoguevara.postit"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Theme colors, so the note follows `omarchy theme set` live.
  readonly property color paper: Color.popups.background
  readonly property color paperEdge: Qt.tint(Color.popups.background, Util.alpha(Color.accent, 0.18))
  readonly property color ink: Color.popups.text
  readonly property color inkSoft: Color.muted

  // UI language: the widget's `language` setting ("es" or "en"), or the
  // system locale when it is "auto" or unset.
  readonly property string lang: {
    var value = String(setting("language", "auto"))
    if (value === "es" || value === "en") return value
    return Qt.locale().name.indexOf("es") === 0 ? "es" : "en"
  }

  readonly property var strings: lang === "es" ? {
    title: "Nota rápida",
    placeholder: "Escribe aquí…",
    hint: "Ctrl+Enter guarda · Esc cierra",
    save: "Guardar",
    saved: "Guardada en ",
    saveFailed: "No se pudo guardar: ",
    fileTitle: "Notas rápidas",
    tooltip: "Nota rápida (clic derecho: abrir en Omawrite)"
  } : {
    title: "Quick note",
    placeholder: "Write here…",
    hint: "Ctrl+Enter saves · Esc closes",
    save: "Save",
    saved: "Saved to ",
    saveFailed: "Could not save: ",
    fileTitle: "Quick notes",
    tooltip: "Quick note (right click: open in Omawrite)"
  }

  readonly property string notesFile: {
    var path = String(setting("file", "~/Documents/" + strings.fileTitle + ".md"))
    if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.substring(1)
    return path
  }

  property string status: ""
  property bool statusError: false

  function open() {
    root.controller.show()
    Qt.callLater(function() { noteArea.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function flash(message, isError) {
    status = message
    statusError = isError === true
    statusTimer.restart()
  }

  // Args: $1 file, $2 document title for a new file. The note text goes over
  // stdin, never argv, so it doesn't show up in process listings.
  function save() {
    var text = noteArea.text.replace(/\s+$/, "")
    if (text.trim() === "" || saveProc.running) return
    saveProc.pendingText = text
    saveProc.stdinEnabled = true
    saveProc.command = [
      "bash", "-c",
      "set -e\n" +
      "f=\"$1\"\n" +
      "note=$(cat)\n" +
      "mkdir -p \"$(dirname \"$f\")\"\n" +
      "[ -s \"$f\" ] || printf '# %s\\n' \"$2\" > \"$f\"\n" +
      "printf '\\n## %s\\n\\n%s\\n' \"$(date '+%Y-%m-%d %H:%M')\" \"$note\" >> \"$f\"",
      "postit", root.notesFile, root.strings.fileTitle
    ]
    saveProc.running = true
  }

  function openInOmawrite() {
    Quickshell.execDetached(["bash", "-c",
      "f=\"$1\"; mkdir -p \"$(dirname \"$f\")\"; [ -e \"$f\" ] || printf '# %s\\n' \"$2\" > \"$f\"; exec setsid uwsm-app -- omawrite \"$f\"",
      "postit", root.notesFile, root.strings.fileTitle])
    root.close()
  }

  Process {
    id: saveProc
    property string pendingText: ""
    stdinEnabled: true
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    // Write the note, then close stdin so `cat` sees EOF.
    onStarted: {
      saveProc.write(saveProc.pendingText)
      saveProc.pendingText = ""
      saveProc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        noteArea.text = ""
        root.flash(root.strings.saved + root.notesFile.split("/").pop(), false)
      } else {
        root.flash(root.strings.saveFailed + String(saveErr.text || "error").trim(), true)
      }
    }
  }

  Timer {
    id: statusTimer
    interval: 2500
    onTriggered: root.status = ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    padding: 0
    borderSpec: Border.none()
    focusTarget: noteArea
    contentWidth: Style.space(340)
    contentHeight: Style.space(300)

    Rectangle {
      id: note
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, 6)
      color: root.paper
      border.color: Color.popups.border
      border.width: 1

      // Tinted strip along the top, where a real post-it's glue sits.
      Rectangle {
        id: glue
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Style.space(28)
        radius: note.radius
        color: root.paperEdge

        Rectangle {
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: note.radius
          color: root.paperEdge
        }

        Text {
          anchors { left: parent.left; leftMargin: Style.space(12); verticalCenter: parent.verticalCenter }
          text: "  " + root.strings.title
          color: root.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          anchors { right: parent.right; rightMargin: Style.space(10); verticalCenter: parent.verticalCenter }
          text: ""
          color: omawriteHover.hovered ? root.ink : root.inkSoft
          font.family: Style.font.family
          font.pixelSize: Style.font.title

          HoverHandler { id: omawriteHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.openInOmawrite() }
        }
      }

      ScrollView {
        id: scroll
        anchors {
          top: glue.bottom; left: parent.left; right: parent.right; bottom: footer.top
          margins: Style.space(12)
        }

        TextArea {
          id: noteArea
          wrapMode: TextEdit.Wrap
          placeholderText: root.strings.placeholder
          placeholderTextColor: root.inkSoft
          color: root.ink
          selectionColor: Style.selectionFillFor(root.ink, Color.accent)
          selectedTextColor: root.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          background: null
          padding: 0

          Keys.onPressed: function(event) {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
              root.save()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            }
          }
        }
      }

      Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(12) }
        height: Style.space(20)

        Text {
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          text: root.status !== "" ? root.status : root.strings.hint
          color: root.statusError ? Color.urgent : root.inkSoft
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          width: parent.width - saveLabel.width - Style.space(8)
        }

        Text {
          id: saveLabel
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          text: root.strings.save
          color: noteArea.text.trim() === "" ? root.inkSoft : Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true

          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.save() }
        }
      }
    }
  }
}
