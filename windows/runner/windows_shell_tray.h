#ifndef RUNNER_WINDOWS_SHELL_TRAY_H_
#define RUNNER_WINDOWS_SHELL_TRAY_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

/// Native Win32 System Tray, Close/Minimize-to-Tray, HKCU Auto-Start and
/// Controlled Exit bridge for MARKET MMS Windows Desktop Client.
class WindowsShellTray {
 public:
  WindowsShellTray(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~WindowsShellTray();

  WindowsShellTray(const WindowsShellTray&) = delete;
  WindowsShellTray& operator=(const WindowsShellTray&) = delete;

  std::optional<LRESULT> HandleMessage(HWND hwnd,
                                       UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam) noexcept;

  void Cleanup();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool InitializeTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayTooltip();
  void RestoreAndFocusWindow();
  void HideWindowToTray();
  void ShowTrayContextMenu();
  void EmitTrayAction(const std::string& action);

  bool IsAutoStartEnabled() const;
  bool SetAutoStartEnabled(bool enabled) const;

  static std::wstring Utf8ToWide(const std::string& utf8);
  static std::wstring TruncateForTray(const std::wstring& value,
                                      size_t max_chars);

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool tray_enabled_ = false;
  bool tray_icon_added_ = false;
  bool allow_close_ = false;
  UINT taskbar_created_msg_ = 0;

  std::wstring hub_status_text_ = L"Hub Durumu: Kontrol ediliyor";
  std::wstring sync_status_text_ = L"Senkronizasyon Durumu: Haz\u0131r";
  std::wstring backup_status_text_ = L"Yedekleme Durumu: Bilgi yok";
  std::wstring tooltip_text_ = L"MARKET MMS";
};

#endif  // RUNNER_WINDOWS_SHELL_TRAY_H_
