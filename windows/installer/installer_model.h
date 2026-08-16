#pragma once

#include <string>

namespace bsl::installer {

enum class PreviewState {
  fresh,
  update,
  repair,
};

enum class InstallerPhase {
  ready,
  installing,
  succeeded,
  failed,
  blocked,
};

enum class InstallerIntent {
  maintain,
  uninstall,
};

struct InstallerModel {
  PreviewState state = PreviewState::fresh;
  InstallerPhase phase = InstallerPhase::ready;
  InstallerIntent intent = InstallerIntent::maintain;
  std::wstring product_name = L"Black Spirit Life";
  std::wstring package_id = L"BlackSpiritLife.App";
  std::wstring version = L"0.1.3";
  std::wstring installed_version;
  std::wstring channel = L"win-x64-stable";
  std::wstring install_path;
  std::wstring message;
  std::wstring retained_log;
  bool remove_personal_data = false;
  bool personal_data_cleanup_pending = false;

  [[nodiscard]] bool path_editable() const {
    return intent == InstallerIntent::maintain &&
           state == PreviewState::fresh &&
           (phase == InstallerPhase::ready || phase == InstallerPhase::failed);
  }

  [[nodiscard]] bool secondary_visible() const {
    return !personal_data_cleanup_pending && state != PreviewState::fresh &&
           phase != InstallerPhase::installing &&
           phase != InstallerPhase::succeeded;
  }

  [[nodiscard]] bool location_visible() const {
    return intent == InstallerIntent::maintain ||
           (intent == InstallerIntent::uninstall &&
            phase == InstallerPhase::ready);
  }

  [[nodiscard]] bool personal_data_choice_visible() const {
    return intent == InstallerIntent::uninstall &&
           phase == InstallerPhase::ready;
  }

  [[nodiscard]] bool close_enabled() const {
    return phase != InstallerPhase::installing;
  }

  [[nodiscard]] std::wstring eyebrow() const {
    if (intent == InstallerIntent::uninstall) {
      switch (phase) {
      case InstallerPhase::ready:
        return L"CONFIRM UNINSTALL";
      case InstallerPhase::installing:
        return L"UNINSTALLING APPLICATION";
      case InstallerPhase::succeeded:
        return L"UNINSTALL COMPLETE";
      case InstallerPhase::failed:
        return personal_data_cleanup_pending ? L"DATA CLEANUP PAUSED"
                                             : L"UNINSTALL PAUSED";
      case InstallerPhase::blocked:
        return L"UNINSTALL BLOCKED";
      }
    }
    switch (phase) {
    case InstallerPhase::installing:
      return L"INSTALLING APPLICATION";
    case InstallerPhase::succeeded:
      return L"INSTALLATION COMPLETE";
    case InstallerPhase::failed:
      return L"INSTALLATION PAUSED";
    case InstallerPhase::blocked:
      return L"INSTALLATION BLOCKED";
    case InstallerPhase::ready:
      break;
    }
    switch (state) {
    case PreviewState::fresh:
      return L"BLACK SPIRIT LIFE INSTALLATION";
    case PreviewState::update:
      return L"BLACK SPIRIT LIFE UPDATE";
    case PreviewState::repair:
      return L"BLACK SPIRIT LIFE REPAIR";
    }
    return {};
  }

  [[nodiscard]] std::wstring heading() const {
    if (intent == InstallerIntent::uninstall) {
      switch (phase) {
      case InstallerPhase::ready:
        return L"Uninstall Black Spirit Life";
      case InstallerPhase::installing:
        return L"Uninstalling Black Spirit Life";
      case InstallerPhase::succeeded:
        return L"Black Spirit Life was uninstalled";
      case InstallerPhase::failed:
        return personal_data_cleanup_pending
                   ? L"Finish removing planner data"
                   : L"Uninstall could not finish";
      case InstallerPhase::blocked:
        return L"Uninstall cannot continue";
      }
    }
    switch (phase) {
    case InstallerPhase::installing:
      return state == PreviewState::update ? L"Updating Black Spirit Life"
             : state == PreviewState::repair
                 ? L"Repairing Black Spirit Life"
                 : L"Installing Black Spirit Life";
    case InstallerPhase::succeeded:
      return L"Black Spirit Life is ready";
    case InstallerPhase::failed:
      return L"Installation could not finish";
    case InstallerPhase::blocked:
      return L"Installation cannot continue";
    case InstallerPhase::ready:
      break;
    }
    switch (state) {
    case PreviewState::fresh:
      return L"Install Black Spirit Life";
    case PreviewState::update:
      return L"Update Black Spirit Life";
    case PreviewState::repair:
      return L"Repair Black Spirit Life";
    }
    return {};
  }

  [[nodiscard]] std::wstring summary() const {
    if (!message.empty())
      return message;
    if (intent == InstallerIntent::uninstall) {
      switch (phase) {
      case InstallerPhase::ready:
        return remove_personal_data
                   ? L"Remove the application and its planner data "
                     L"from this PC?"
                   : L"Remove the application files? Your planner data will "
                     L"stay on this PC.";
      case InstallerPhase::installing:
        return L"Please keep this window open.";
      case InstallerPhase::succeeded:
        return remove_personal_data
                   ? L"The application was removed. Its planner data was "
                     L"sent to the Recycle Bin."
                   : L"The application was removed. Your planner data "
                     L"remains on this PC.";
      case InstallerPhase::failed:
        return L"Review the message, then try again.";
      case InstallerPhase::blocked:
        return L"Nothing was changed.";
      }
    }
    switch (phase) {
    case InstallerPhase::installing:
      return L"Please keep this window open.";
    case InstallerPhase::succeeded:
      return L"Version " + version + L" was installed successfully.";
    case InstallerPhase::failed:
      return L"Review the message, then try again.";
    case InstallerPhase::blocked:
      return L"Nothing was changed.";
    case InstallerPhase::ready:
      break;
    }
    switch (state) {
    case PreviewState::fresh:
      return L"Choose where the application should be installed.";
    case PreviewState::update:
      return L"Version " + installed_version +
             L" is installed. This will update it to " + version + L".";
    case PreviewState::repair:
      return L"Restore the application files without changing your planner "
             L"data.";
    }
    return {};
  }

  [[nodiscard]] std::wstring footer() const {
    if (phase == InstallerPhase::installing) {
      return intent == InstallerIntent::uninstall ? L"Uninstalling..."
                                                   : L"Installing...";
    }
    if (phase == InstallerPhase::succeeded) {
      return intent == InstallerIntent::uninstall ? L"Application removed"
                                                   : L"Ready to open";
    }
    if (phase == InstallerPhase::failed && !retained_log.empty()) {
      return L"A diagnostic log was kept for this attempt.";
    }
    if (phase == InstallerPhase::blocked)
      return L"No files were changed";
    return {};
  }

  [[nodiscard]] std::wstring primary_label() const {
    if (intent == InstallerIntent::uninstall) {
      switch (phase) {
      case InstallerPhase::ready:
        return remove_personal_data ? L"Uninstall and delete data"
                                    : L"Uninstall";
      case InstallerPhase::installing:
        return L"Uninstalling...";
      case InstallerPhase::succeeded:
        return L"Close";
      case InstallerPhase::failed:
        return personal_data_cleanup_pending ? L"Finish cleanup"
                                             : L"Try again";
      case InstallerPhase::blocked:
        return L"Close";
      }
    }
    switch (phase) {
    case InstallerPhase::installing:
      return L"Installing...";
    case InstallerPhase::succeeded:
      return L"Open Black Spirit Life";
    case InstallerPhase::failed:
      return L"Try again";
    case InstallerPhase::blocked:
      return L"Close";
    case InstallerPhase::ready:
      break;
    }
    switch (state) {
    case PreviewState::fresh:
      return L"Install";
    case PreviewState::update:
      return L"Update";
    case PreviewState::repair:
      return L"Repair";
    }
    return {};
  }

  [[nodiscard]] std::wstring secondary_label() const {
    return intent == InstallerIntent::uninstall ? L"Back" : L"Uninstall";
  }
};

} // namespace bsl::installer
