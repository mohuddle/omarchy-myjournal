import QtQuick

Item {
  id: root
  property color foreground: "#d4b15a"
  property real size: 16
  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      var s = Math.min(width, height)
      var x0 = (width - s) / 2
      var y0 = (height - s) / 2
      ctx.reset()
      ctx.strokeStyle = root.foreground
      ctx.fillStyle = "transparent"
      ctx.lineWidth = Math.max(1.2, s * 0.08)
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      var pad = s * 0.14
      ctx.strokeRect(x0 + pad, y0 + pad * 0.7, s - pad * 2, s - pad * 1.5)
      ctx.beginPath()
      ctx.moveTo(x0 + pad * 2.1, y0 + s * 0.38)
      ctx.lineTo(x0 + s - pad * 2.1, y0 + s * 0.38)
      ctx.moveTo(x0 + pad * 2.1, y0 + s * 0.55)
      ctx.lineTo(x0 + s - pad * 2.1, y0 + s * 0.55)
      ctx.moveTo(x0 + pad * 2.1, y0 + s * 0.72)
      ctx.lineTo(x0 + s - pad * 2.8, y0 + s * 0.72)
      ctx.stroke()
    }
  }

  onForegroundChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  Component.onCompleted: canvas.requestPaint()
}
