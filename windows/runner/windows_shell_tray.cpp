#include "windows_shell_tray.h"

#include <shellapi.h>

#include <flutter/standard_method_codec.h>

#include <vector>

#include "resource.h"

namespace {

constexpr char kChannelName[] = "com.marketmms.market_pos/windows_shell";
constexpr UINT kTrayCallbackMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1001;

constexpr UINT_PTR kMenuOpenApp = 2001;
constexpr UINT_PTR kMenuHubStatus = 2002;
constexpr UINT_PTR kMenuSyncStatus = 2003;
constexpr UINT_PTR kMenuBackupStatus = 2004;
constexpr UINT_PTR kMenuSettings = 2005;
constexpr UINT_PTR kMenuExitApp = 2006;

constexpr wchar_t kAutoStartRegSubkey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kAutoStartValueName[] = L"MarketMMSClient";

}  // namespace

WindowsShellTray::WindowsShellTray(HWND hwnd,
                                   flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd),
      taskbar_created_msg_(RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowsShellTray::~WindowsShellTray() {
  Cleanup();
}

void WindowsShellTray::Cleanup() {
  RemoveTrayIcon();
  tray_enabled_ = false;
}

void WindowsShellTray::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "initializeTray") {
    const bool ok = InitializeTrayIcon();
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "updateTrayStatus") {
    if (const auto* map =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto readString = [&](const char* key) -> std::optional<std::wstring> {
        auto it = map->find(flutter::EncodableValue(key));
        if (it == map->end()) return std::nullopt;
        if (const auto* s = std::get_if<std::string>(&it->second)) {
          return Utf8ToWide(*s);
        }
        return std::nullopt;
      };
      if (auto v = readString("hubStatus")) {
        hub_status_text_ = TruncateForTray(*v, 96);
      }
      if (auto v = readString("syncStatus")) {
        sync_status_text_ = TruncateForTray(*v, 96);
      }
      if (auto v = readString("backupStatus")) {
        backup_status_text_ = TruncateForTray(*v, 96);
      }
      if (auto v = readString("tooltip")) {
        tooltip_text_ = TruncateForTray(*v, 120);
      }
      UpdateTrayTooltip();
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "showWindow") {
    RestoreAndFocusWindow();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "hideToTray") {
    HideWindowToTray();
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "confirmExit") {
    allow_close_ = true;
    tray_enabled_ = false;
    RemoveTrayIcon();
    result->Success(flutter::EncodableValue(true));
    if (hwnd_ != nullptr && IsWindow(hwnd_)) {
      PostMessageW(hwnd_, WM_CLOSE, 0, 0);
    }
    return;
  }

  if (method == "getAutoStartEnabled") {
    result->Success(flutter::EncodableValue(IsAutoStartEnabled()));
    return;
  }

  if (method == "setAutoStartEnabled") {
    bool enabled = false;
    if (const auto* arg = std::get_if<bool>(call.arguments())) {
      enabled = *arg;
    } else if (const auto* map =
                   std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = map->find(flutter::EncodableValue("enabled"));
      if (it != map->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) {
          enabled = *b;
        }
      }
    }
    const bool ok = SetAutoStartEnabled(enabled);
    if (ok) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("AUTOSTART_WRITE_FAILED",
                    "Windows otomatik baslatma kaydi guncellenemedi.");
    }
    return;
  }

  if (method == "isTrayActive") {
    result->Success(flutter::EncodableValue(tray_icon_added_));
    return;
  }

  result->NotImplemented();
}

std::optional<LRESULT> WindowsShellTray::HandleMessage(HWND hwnd,
                                                       UINT message,
                                                       WPARAM wparam,
                                                       LPARAM lparam) noexcept {
  if (message == taskbar_created_msg_ && taskbar_created_msg_ != 0) {
    if (tray_enabled_) {
      tray_icon_added_ = false;
      InitializeTrayIcon();
    }
    return std::nullopt;
  }

  switch (message) {
    case WM_CLOSE:
      if (tray_enabled_ && !allow_close_) {
        HideWindowToTray();
        return 0;
      }
      break;

    case WM_SYSCOMMAND:
      if (tray_enabled_ && !allow_close_ &&
          (wparam & 0xFFF0) == SC_MINIMIZE) {
        HideWindowToTray();
        return 0;
      }
      break;

    case WM_QUERYENDSESSION:
      // Do not block Windows shutdown/logoff.
      allow_close_ = true;
      tray_enabled_ = false;
      break;

    case kTrayCallbackMessage: {
      const UINT tray_event = LOWORD(lparam);
      if (tray_event == WM_LBUTTONDBLCLK) {
        RestoreAndFocusWindow();
        EmitTrayAction("openApp");
        return 0;
      }
      if (tray_event == WM_RBUTTONUP || tray_event == WM_CONTEXTMENU) {
        ShowTrayContextMenu();
        return 0;
      }
      break;
    }

    case WM_COMMAND: {
      const UINT cmd = LOWORD(wparam);
      switch (cmd) {
        case kMenuOpenApp:
          RestoreAndFocusWindow();
          EmitTrayAction("openApp");
          return 0;
        case kMenuHubStatus:
          RestoreAndFocusWindow();
          EmitTrayAction("openHubStatus");
          return 0;
        case kMenuSyncStatus:
          RestoreAndFocusWindow();
          EmitTrayAction("openSyncStatus");
          return 0;
        case kMenuBackupStatus:
          RestoreAndFocusWindow();
          EmitTrayAction("openBackupStatus");
          return 0;
        case kMenuSettings:
          RestoreAndFocusWindow();
          EmitTrayAction("openSettings");
          return 0;
        case kMenuExitApp:
          EmitTrayAction("requestExit");
          return 0;
        default:
          break;
      }
      break;
    }
  }

  return std::nullopt;
}

bool WindowsShellTray::InitializeTrayIcon() {
  if (hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return false;
  }
  tray_enabled_ = true;
  if (tray_icon_added_) {
    UpdateTrayTooltip();
    return true;
  }

  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMessage;
  nid.hIcon =
      LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));

  const std::wstring tip = TruncateForTray(tooltip_text_, 120);
  wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);

  if (!Shell_NotifyIconW(NIM_ADD, &nid)) {
    return false;
  }

  nid.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &nid);
  tray_icon_added_ = true;
  return true;
}

void WindowsShellTray::RemoveTrayIcon() {
  if (!tray_icon_added_ || hwnd_ == nullptr) {
    tray_icon_added_ = false;
    return;
  }
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_icon_added_ = false;
}

void WindowsShellTray::UpdateTrayTooltip() {
  if (!tray_icon_added_ || hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return;
  }
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_TIP;
  const std::wstring tip = TruncateForTray(tooltip_text_, 120);
  wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

void WindowsShellTray::RestoreAndFocusWindow() {
  if (hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return;
  }
  if (IsIconic(hwnd_)) {
    ShowWindow(hwnd_, SW_RESTORE);
  } else {
    ShowWindow(hwnd_, SW_SHOW);
  }
  SetForegroundWindow(hwnd_);
}

void WindowsShellTray::HideWindowToTray() {
  if (hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return;
  }
  ShowWindow(hwnd_, SW_HIDE);
}

void WindowsShellTray::ShowTrayContextMenu() {
  if (hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kMenuOpenApp, L"MARKET MMS'i A\u00E7");
  SetMenuDefaultItem(menu, kMenuOpenApp, FALSE);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuHubStatus, hub_status_text_.c_str());
  AppendMenuW(menu, MF_STRING, kMenuSyncStatus, sync_status_text_.c_str());
  AppendMenuW(menu, MF_STRING, kMenuBackupStatus, backup_status_text_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuSettings, L"Ayarlar");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExitApp, L"Uygulamadan \u00C7\u0131k");

  POINT pt{};
  GetCursorPos(&pt);

  SetForegroundWindow(hwnd_);
  TrackPopupMenu(menu,
                 TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN,
                 pt.x, pt.y, 0, hwnd_, nullptr);
  PostMessageW(hwnd_, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void WindowsShellTray::EmitTrayAction(const std::string& action) {
  if (!channel_) return;
  channel_->InvokeMethod(
      "onTrayAction",
      std::make_unique<flutter::EncodableValue>(action));
}

bool WindowsShellTray::IsAutoStartEnabled() const {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kAutoStartRegSubkey, 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return false;
  }

  DWORD type = 0;
  DWORD size_bytes = 0;
  const LSTATUS q = RegQueryValueExW(key, kAutoStartValueName, nullptr, &type,
                                     nullptr, &size_bytes);
  RegCloseKey(key);
  return q == ERROR_SUCCESS && (type == REG_SZ || type == REG_EXPAND_SZ) &&
         size_bytes > sizeof(wchar_t);
}

bool WindowsShellTray::SetAutoStartEnabled(bool enabled) const {
  if (enabled) {
    std::vector<wchar_t> exe_path(MAX_PATH, L'\0');
    DWORD len = GetModuleFileNameW(nullptr, exe_path.data(),
                                   static_cast<DWORD>(exe_path.size()));
    while (len == exe_path.size() &&
           GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
      exe_path.resize(exe_path.size() * 2, L'\0');
      len = GetModuleFileNameW(nullptr, exe_path.data(),
                               static_cast<DWORD>(exe_path.size()));
    }
    if (len == 0) {
      return false;
    }

    const std::wstring command_line =
        L"\"" + std::wstring(exe_path.data(), len) + L"\"";

    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kAutoStartRegSubkey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
      return false;
    }
    const DWORD byte_len =
        static_cast<DWORD>((command_line.size() + 1) * sizeof(wchar_t));
    const LSTATUS set_res = RegSetValueExW(
        key, kAutoStartValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command_line.c_str()), byte_len);
    RegCloseKey(key);
    return set_res == ERROR_SUCCESS;
  }

  HKEY key = nullptr;
  const LSTATUS open_res = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoStartRegSubkey,
                                         0, KEY_SET_VALUE, &key);
  if (open_res == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  if (open_res != ERROR_SUCCESS) {
    return false;
  }
  const LSTATUS del_res = RegDeleteValueW(key, kAutoStartValueName);
  RegCloseKey(key);
  return del_res == ERROR_SUCCESS || del_res == ERROR_FILE_NOT_FOUND;
}

std::wstring WindowsShellTray::Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int count = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), count);
  return out;
}

std::wstring WindowsShellTray::TruncateForTray(const std::wstring& value,
                                               size_t max_chars) {
  if (value.size() <= max_chars) return value;
  if (max_chars <= 3) return value.substr(0, max_chars);
  return value.substr(0, max_chars - 3) + L"...";
}
