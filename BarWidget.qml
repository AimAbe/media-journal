import QtQuick
import qs.Ui

// Bar button that toggles the media journal menu.
//
// Icon-only bar-widgets (bluetooth, network, audio, power, monitor, tray,
// system-update, ...) all build on qs.Ui.BarIconButton, not the bare
// WidgetButton — it adds the uniform icon-slot sizing (Style.bar.iconSlot),
// the shared icon font size (Style.bar.iconFont), and optical glyph
// centering (via OpticalGlyph) that make every icon-only widget line up and
// weigh the same regardless of that glyph's own font metrics. Plain
// WidgetButton sizes off text-label metrics instead, which is right for a
// widget with a real text label (a clock, a keyboard-layout code) but is
// exactly why this one sat slightly off next to its neighbors. Color comes
// through the same `bar.barForeground` binding either way, so switching to
// BarIconButton is what actually makes it track the active theme the same
// way every other icon does — same code path, not just the same color value.
//
// The click itself still shells out to `omarchy-shell shell toggle <id>
// <payload>` via bar.run() rather than bar.shell.toggle(...) in-process,
// matching every first-party widget's own convention (e.g. bluetooth's
// BarIconButton below calls root.toggle(), which itself is this same
// shell-out pattern one layer up).
BarWidget {
  id: root
  moduleName: "aimen.mediajournal"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font glyph (md-pencil_box, from the bar's own icon font), not an
    // emoji — an emoji renders full-color regardless of `color:`, which is
    // exactly why the original 📖 looked out of place next to the bar's
    // flat, theme-colored icons.
    text: "\u{f03ec}"
    tooltipText: "Media Journal"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle aimen.mediajournal '{}'")
    }
  }
}
