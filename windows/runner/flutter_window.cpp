#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Frame bridge: Dart calls setFrameColors({...}) as the window moves between
  // the launch film and each studio theme (setDarkTheme(bool) still works).
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "photon/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setDarkTheme") {
          const bool* is_dark = std::get_if<bool>(call.arguments());
          if (is_dark == nullptr) {
            result->Error("bad-args", "setDarkTheme expects a bool");
            return;
          }
          Win32Window::UpdateTheme(GetHandle(), *is_dark);
          result->Success();
        } else if (call.method_name() == "setFrameColors") {
          // {dark: bool, caption: int, text: int, border: int}, colours as
          // 0xRRGGBB: the launch film's frame, then each studio theme's.
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("bad-args", "setFrameColors expects a map");
            return;
          }
          auto number = [args](const char* key, int64_t fallback) -> int64_t {
            auto it = args->find(flutter::EncodableValue(key));
            if (it == args->end()) return fallback;
            if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
            if (const auto* v = std::get_if<int64_t>(&it->second)) return *v;
            return fallback;
          };
          auto colorref = [](int64_t rgb) -> COLORREF {
            const BYTE r = static_cast<BYTE>((rgb >> 16) & 0xFF);
            const BYTE g = static_cast<BYTE>((rgb >> 8) & 0xFF);
            const BYTE b = static_cast<BYTE>(rgb & 0xFF);
            return RGB(r, g, b);
          };
          bool dark = true;
          auto dark_it = args->find(flutter::EncodableValue("dark"));
          if (dark_it != args->end()) {
            if (const auto* v = std::get_if<bool>(&dark_it->second)) dark = *v;
          }
          Win32Window::UpdateFrame(GetHandle(), dark,
                                   colorref(number("caption", 0x0E0E10)),
                                   colorref(number("text", 0xF0F1FA)),
                                   colorref(number("border", 0x262936)));
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
