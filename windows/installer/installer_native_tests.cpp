#include <windows.h>

#include <shellapi.h>

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "beta_maintenance_gate.h"
#include "install_path_policy.h"
#include "install_process_guard.h"
#include "installed_beta_locator.h"
#include "installer_build_config.h"
#include "personal_data_removal.h"

namespace {

bool Require(bool condition, const char *message) {
  if (!condition)
    std::cerr << message << '\n';
  return condition;
}

bool WriteText(const std::filesystem::path &path, const std::string &value) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output.write(value.data(), static_cast<std::streamsize>(value.size()));
  output.flush();
  return output.good();
}

std::string JsonEscape(const std::wstring &value) {
  std::string result;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      result += "\\\\";
    } else if (character >= 0x20 && character <= 0x7e && character != L'\"') {
      result.push_back(static_cast<char>(character));
    } else {
      return {};
    }
  }
  return result;
}

std::wstring Quote(const std::wstring &value) { return L"\"" + value + L"\""; }

std::wstring ShortPathIfAvailable(const std::filesystem::path &path) {
  const DWORD required = GetShortPathNameW(path.c_str(), nullptr, 0);
  if (required == 0)
    return {};
  std::wstring result(required, L'\0');
  const DWORD written =
      GetShortPathNameW(path.c_str(), result.data(), required);
  if (written == 0 || written >= required)
    return {};
  result.resize(written);
  return _wcsicmp(result.c_str(), path.c_str()) == 0 ? std::wstring{} : result;
}

DWORD RunChild(const std::filesystem::path &executable,
               const std::wstring &arguments) {
  std::wstring command = Quote(executable.wstring()) + L" " + arguments;
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), mutable_command.data(), nullptr,
                      nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                      &startup, &process)) {
    return MAXDWORD;
  }
  const DWORD wait = WaitForSingleObject(process.hProcess, 10000);
  DWORD exit_code = MAXDWORD;
  if (wait == WAIT_OBJECT_0)
    GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return exit_code;
}

int RunHelperMode(int argc, wchar_t **argv) {
  if (argc >= 2 && std::wstring(argv[1]) == L"--try-gate") {
    bsl::windows::BetaMaintenanceGate gate;
    std::wstring error;
    return gate.TryAcquire(&error) ? 0 : 23;
  }
  if (argc == 4 && std::wstring(argv[1]) == L"--wait-events") {
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[2]);
    HANDLE stop = OpenEventW(SYNCHRONIZE, FALSE, argv[3]);
    if (ready == nullptr || stop == nullptr)
      return 24;
    SetEvent(ready);
    const DWORD wait = WaitForSingleObject(stop, 10000);
    CloseHandle(ready);
    CloseHandle(stop);
    return wait == WAIT_OBJECT_0 ? 0 : 25;
  }
  return -1;
}

bool WriteInstalledRemovalFixture(const std::filesystem::path &root,
                                  const std::string &version) {
  const std::filesystem::path current = root / L"current";
  const std::string manifest =
      "<package><metadata><id>BlackSpiritLife.App</id>"
      "<channel>win-x64-stable</channel>"
      "<mainExe>BlackSpiritLife.exe</mainExe><version>" +
      version + "</version></metadata></package>";
  return WriteText(root / L"Update.exe", "MZ") &&
         WriteText(root / L"BlackSpiritLife.exe", "MZ") &&
         WriteText(current / L"BlackSpiritLife.exe", "MZ") &&
         WriteText(current / L"BlackSpiritLifeUpdater.exe", "MZ") &&
         WriteText(current / L"sq.version", manifest);
}

bool ParkInstalledRemovalFixture(const std::filesystem::path &root) {
  const std::array<std::filesystem::path, 4> files = {
      root / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLifeUpdater.exe",
      root / L"current" / L"sq.version",
  };
  std::error_code error;
  for (const auto &file : files) {
    std::filesystem::rename(file, file.wstring() + L".removed", error);
    if (error)
      return false;
  }
  return true;
}

bool RunPersonalDataRemovalTests(const std::filesystem::path &test_root) {
  using namespace bsl::installer;
  bool passed = true;
  const std::filesystem::path fixture = test_root / L"Personal Data Removal";
  const std::filesystem::path roaming = fixture / L"Roaming";
  const std::filesystem::path local = fixture / L"Local";
  const std::filesystem::path journal =
      local / L"BlackSpiritLife.App.Removal";
  const std::filesystem::path install = fixture / L"Installed App";
  const std::filesystem::path profile =
      roaming / L"Black Spirit Life";
  const std::filesystem::path local_data =
      local / L"Black Spirit Life";
  const std::filesystem::path former_beta =
      roaming / L"Black Spirit Life Beta";
  const std::filesystem::path former =
      roaming / L"BDO Craft Planner Map Candidate";
  passed &= Require(
      WriteInstalledRemovalFixture(install, "0.1.0") &&
          WriteText(profile / L"planner-state.json", "{\"owned\":true}") &&
          WriteText(local_data / L"Map Cache" / L"tile.bin", "tile") &&
          WriteText(former_beta / L"keep.txt", "former-beta") &&
          WriteText(former / L"keep.txt", "former"),
      "Personal-data removal fixtures could not be written.");
  const PersonalDataRemovalTestEnvironment environment{
      .roaming_app_data = roaming.wstring(),
      .local_app_data = local.wstring(),
      .journal_directory = journal.wstring(),
  };

  PersonalDataRemovalPlan canceled_plan;
  const auto prepared_for_cancel = PreparePersonalDataRemovalForTesting(
      environment, install.wstring(), &canceled_plan);
  passed &= Require(prepared_for_cancel.success &&
                         prepared_for_cancel.status ==
                             PersonalDataRemovalStatus::prepared &&
                         std::filesystem::exists(canceled_plan.journal_mirror_path),
                     "Durable removal consent was not prepared.");
  passed &= Require(
      PreparedPersonalDataRemovalMatchesInstallation(
          canceled_plan, install.wstring(), install.wstring(),
          L"0.1.0", canceled_plan.install_root_volume_serial,
          canceled_plan.install_root_file_id) &&
          !PreparedPersonalDataRemovalMatchesInstallation(
              canceled_plan, install.wstring(), install.wstring(),
              L"0.1.0", canceled_plan.install_root_volume_serial,
              canceled_plan.install_root_file_id + 1) &&
          !PreparedPersonalDataRemovalMatchesInstallation(
              canceled_plan, install.wstring(), install.wstring(),
              L"0.1.1", canceled_plan.install_root_volume_serial,
              canceled_plan.install_root_file_id),
      "Prepared consent did not reject a replacement installation identity.");

  HANDLE primary_lock = CreateFileW(
      canceled_plan.journal_path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  PersonalDataRemovalResult locked_cancel;
  if (primary_lock != INVALID_HANDLE_VALUE) {
    locked_cancel =
        CancelPreparedPersonalDataRemovalForTesting(canceled_plan);
    CloseHandle(primary_lock);
  }
  passed &= Require(
      primary_lock != INVALID_HANDLE_VALUE && !locked_cancel.success &&
          locked_cancel.status == PersonalDataRemovalStatus::prepared &&
          std::filesystem::exists(canceled_plan.journal_mirror_path),
      "A working-journal delete failure discarded the authoritative mirror.");
  PersonalDataRemovalPlan detected_after_locked_cancel;
  const auto detected_cancel = DetectPendingPersonalDataRemovalForTesting(
      environment, &detected_after_locked_cancel);
  passed &= Require(detected_cancel.success &&
                         detected_cancel.status ==
                             PersonalDataRemovalStatus::prepared,
                     "Consent was not recoverable after a locked clear.");
  const auto canceled = CancelPreparedPersonalDataRemovalForTesting(
      detected_after_locked_cancel);
  passed &= Require(canceled.success &&
                        canceled.status == PersonalDataRemovalStatus::none &&
                        std::filesystem::exists(profile) &&
                        std::filesystem::exists(local_data) &&
                        !std::filesystem::exists(canceled_plan.journal_path) &&
                        !std::filesystem::exists(
                            canceled_plan.journal_mirror_path),
                    "A fully prepared removal could not be canceled safely.");

  const std::string default_locator =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\",\"applicationDirectory\":\"" +
      JsonEscape(profile.wstring()) + "\"}";
  const std::filesystem::path default_bootstrap = local_data / L"Bootstrap";
  passed &= Require(
      WriteText(default_bootstrap / L"personal-data-location.json",
                default_locator) &&
          WriteText(default_bootstrap /
                        L"personal-data-location.committed.json",
                    default_locator),
      "Move-back-to-default locator fixtures could not be written.");
  PersonalDataRemovalPlan moved_back_plan;
  const auto moved_back_prepared = PreparePersonalDataRemovalForTesting(
      environment, install.wstring(), &moved_back_plan);
  passed &= Require(
      moved_back_prepared.success && !moved_back_plan.custom_profile &&
          CancelPreparedPersonalDataRemovalForTesting(moved_back_plan).success,
      "A profile moved back to the default folder was treated as custom.");

  PersonalDataRemovalPlan plan;
  const auto prepared = PreparePersonalDataRemovalForTesting(
      environment, install.wstring(), &plan);
  passed &= Require(prepared.success && plan.active_profile.present &&
                         plan.local_data.present && !plan.custom_profile,
                     "The exact default application data scope was not captured.");
  const std::wstring stale_stage_suffix =
      L".uninstall.00000000000000000000000000000000.tmp";
  passed &= Require(
      WriteText(std::filesystem::path(plan.journal_path + stale_stage_suffix),
                "stale") &&
          WriteText(std::filesystem::path(plan.journal_mirror_path +
                                          stale_stage_suffix),
                    "stale") &&
          WriteText(std::filesystem::path(plan.reset_marker_path +
                                          stale_stage_suffix),
                    "stale"),
      "Stale durable-stage fixtures could not be written.");
  passed &= Require(ParkInstalledRemovalFixture(install),
                     "The isolated uninstall postcondition could not be staged.");
  const auto marked = MarkPersonalDataApplicationRemovedForTesting(plan);
  passed &= Require(marked.success && marked.application_removed,
                    "A complete isolated application removal was not recorded.");
  const std::filesystem::path recycle = fixture / L"Recycle Bin";
  int recycled_count = 0;
  const PersonalDataRecycleCallback recycle_fixture =
      [&](const std::wstring &path, std::wstring *error) {
        std::error_code move_error;
        std::filesystem::create_directories(recycle, move_error);
        if (move_error) {
          if (error)
            *error = L"The isolated recycle fixture could not be created.";
          return false;
        }
        const std::filesystem::path destination =
            recycle / (L"entry-" + std::to_wstring(++recycled_count));
        std::filesystem::rename(path, destination, move_error);
        if (move_error && error)
          *error = L"The isolated quarantine could not be recycled.";
        return !move_error;
      };
  const auto finalized =
      FinalizePersonalDataRemovalForTesting(plan, recycle_fixture);
  const std::filesystem::path reset_marker =
      profile / L".black-spirit-life-intentional-reset.json";
  passed &= Require(
      finalized.success && finalized.removed && recycled_count == 2 &&
          !std::filesystem::exists(profile / L"planner-state.json") &&
          std::filesystem::exists(reset_marker) &&
          !std::filesystem::exists(local_data) &&
          std::filesystem::exists(former_beta / L"keep.txt") &&
          std::filesystem::exists(former / L"keep.txt") &&
          !std::filesystem::exists(plan.journal_path) &&
          !std::filesystem::exists(plan.journal_mirror_path),
      "Default planner data did not reach the isolated Recycle Bin safely.");

  const std::filesystem::path retry_fixture =
      test_root / L"Personal Data Removal Retry";
  const std::filesystem::path retry_roaming = retry_fixture / L"Roaming";
  const std::filesystem::path retry_local = retry_fixture / L"Local";
  const std::filesystem::path retry_journal =
      retry_local / L"BlackSpiritLife.App.Removal";
  const std::filesystem::path retry_install =
      retry_fixture / L"Installed App";
  const std::filesystem::path custom_profile =
      retry_fixture / L"Custom Planner Data";
  const std::filesystem::path retry_local_data =
      retry_local / L"Black Spirit Life";
  const std::string custom_marker =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\",\"profile\":true,"
      "\"profileId\":\"profile-1-0123456789abcdef0123456789abcdef\","
      "\"transactionId\":\"move-1-fedcba9876543210fedcba9876543210\"}";
  const std::string locator =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\",\"applicationDirectory\":\"" +
      JsonEscape(custom_profile.wstring()) + "\"}";
  const std::filesystem::path retry_bootstrap =
      retry_local_data / L"Bootstrap";
  passed &= Require(
      WriteInstalledRemovalFixture(retry_install, "0.1.0") &&
          WriteText(custom_profile / L"planner-state.json", "{\"owned\":true}") &&
          WriteText(custom_profile / L".black-spirit-life-profile.json",
                    custom_marker) &&
          WriteText(retry_local_data / L"Map Cache" / L"tile.bin", "tile") &&
          WriteText(retry_bootstrap / L"personal-data-location.json", locator) &&
          WriteText(retry_bootstrap /
                        L"personal-data-location.committed.json",
                    locator),
      "Custom-profile retry fixtures could not be written.");
  const PersonalDataRemovalTestEnvironment retry_environment{
      .roaming_app_data = retry_roaming.wstring(),
      .local_app_data = retry_local.wstring(),
      .journal_directory = retry_journal.wstring(),
  };
  PersonalDataRemovalPlan retry_plan;
  const auto retry_prepared = PreparePersonalDataRemovalForTesting(
      retry_environment, retry_install.wstring(), &retry_plan);
  passed &= Require(retry_prepared.success && retry_plan.custom_profile &&
                        retry_plan.active_profile.path ==
                            custom_profile.wstring(),
                    "The verified custom profile was not captured exactly.");
  passed &= Require(ParkInstalledRemovalFixture(retry_install) &&
                        MarkPersonalDataApplicationRemovedForTesting(retry_plan)
                            .success,
                    "The retry fixture could not enter application-removed state.");
  const PersonalDataRecycleCallback retain_quarantine =
      [](const std::wstring &, std::wstring *error) {
        if (error)
          *error = L"Simulated Recycle Bin outage.";
        return false;
      };
  const auto retained = FinalizePersonalDataRemovalForTesting(
      retry_plan, retain_quarantine);
  passed &= Require(!retained.success && retained.retained_quarantine &&
                         retained.retry_available &&
                        !std::filesystem::exists(custom_profile) &&
                        std::filesystem::exists(
                            retry_plan.active_profile.quarantine_path) &&
                        std::filesystem::exists(retry_plan.journal_mirror_path),
                     "A Recycle Bin failure did not retain a retryable quarantine.");
  const std::filesystem::path displaced_quarantine =
      retry_fixture / L"Displaced planner quarantine";
  std::error_code displace_error;
  std::filesystem::rename(retry_plan.active_profile.quarantine_path,
                          displaced_quarantine, displace_error);
  int unexpected_recycle_calls = 0;
  PersonalDataRemovalResult missing_quarantine;
  if (!displace_error) {
    missing_quarantine = RetryPendingPersonalDataRemovalForTesting(
        retry_environment,
        [&](const std::wstring &, std::wstring *) {
          ++unexpected_recycle_calls;
          return true;
        });
  }
  passed &= Require(
      !displace_error && !missing_quarantine.success &&
          !missing_quarantine.removed && unexpected_recycle_calls == 0 &&
          !std::filesystem::exists(
              retry_roaming / L"Black Spirit Life" /
              L".black-spirit-life-intentional-reset.json"),
      "A missing quarantine was falsely reported as reaching the Recycle Bin.");
  std::error_code restore_quarantine_error;
  if (!displace_error) {
    std::filesystem::rename(displaced_quarantine,
                            retry_plan.active_profile.quarantine_path,
                            restore_quarantine_error);
  }
  passed &= Require(!restore_quarantine_error,
                    "The isolated quarantine fixture could not be restored.");
  int retry_recycled = 0;
  const PersonalDataRecycleCallback retry_recycle =
      [&](const std::wstring &path, std::wstring *error) {
        std::error_code move_error;
        const std::filesystem::path retry_bin = retry_fixture / L"Recycle Bin";
        std::filesystem::create_directories(retry_bin, move_error);
        if (!move_error) {
          std::filesystem::rename(
              path, retry_bin / (L"entry-" +
                                 std::to_wstring(++retry_recycled)),
              move_error);
        }
        if (move_error && error)
          *error = L"The retry quarantine could not be recycled.";
        return !move_error;
      };
  const auto retried = RetryPendingPersonalDataRemovalForTesting(
      retry_environment, retry_recycle);
  passed &= Require(retried.success && retried.removed &&
                         retry_recycled == 2 &&
                        !std::filesystem::exists(custom_profile) &&
                        !std::filesystem::exists(retry_local_data) &&
                        std::filesystem::exists(
                            retry_roaming / L"Black Spirit Life" /
                            L".black-spirit-life-intentional-reset.json"),
                     "A retained personal-data quarantine did not resume safely.");

  const std::filesystem::path drift_fixture =
      test_root / L"Personal Data Removal Control Drift";
  const std::filesystem::path drift_roaming = drift_fixture / L"Roaming";
  const std::filesystem::path drift_local = drift_fixture / L"Local";
  const std::filesystem::path drift_journal =
      drift_local / L"BlackSpiritLife.App.Removal";
  const std::filesystem::path drift_install = drift_fixture / L"Installed App";
  const std::filesystem::path drift_profile =
      drift_roaming / L"Black Spirit Life";
  const std::filesystem::path drift_local_data =
      drift_local / L"Black Spirit Life";
  passed &= Require(
      WriteInstalledRemovalFixture(drift_install, "0.1.0") &&
          WriteText(drift_profile / L"planner-state.json", "{\"owned\":true}") &&
          WriteText(drift_local_data / L"Map Cache" / L"tile.bin", "tile"),
      "Removal-control identity-drift fixtures could not be written.");
  const PersonalDataRemovalTestEnvironment drift_environment{
      .roaming_app_data = drift_roaming.wstring(),
      .local_app_data = drift_local.wstring(),
      .journal_directory = drift_journal.wstring(),
  };
  PersonalDataRemovalPlan drift_plan;
  const auto drift_prepared = PreparePersonalDataRemovalForTesting(
      drift_environment, drift_install.wstring(), &drift_plan);
  const std::filesystem::path parked_journal =
      drift_local / L"Parked removal control";
  std::error_code drift_error;
  if (drift_prepared.success) {
    std::filesystem::rename(drift_journal, parked_journal, drift_error);
    if (!drift_error)
      std::filesystem::create_directories(drift_journal, drift_error);
    if (!drift_error) {
      std::filesystem::copy_file(
          parked_journal /
              std::filesystem::path(drift_plan.journal_path).filename(),
          std::filesystem::path(drift_plan.journal_path),
          std::filesystem::copy_options::overwrite_existing, drift_error);
    }
    if (!drift_error) {
      std::filesystem::copy_file(
          parked_journal /
              std::filesystem::path(drift_plan.journal_mirror_path).filename(),
          std::filesystem::path(drift_plan.journal_mirror_path),
          std::filesystem::copy_options::overwrite_existing, drift_error);
    }
  }
  PersonalDataRemovalPlan rejected_drift_plan;
  const auto rejected_drift = DetectPendingPersonalDataRemovalForTesting(
      drift_environment, &rejected_drift_plan);
  passed &= Require(
      drift_prepared.success && !drift_error && !rejected_drift.success &&
          rejected_drift.status == PersonalDataRemovalStatus::invalid &&
          std::filesystem::exists(drift_profile / L"planner-state.json") &&
          std::filesystem::exists(drift_local_data / L"Map Cache" / L"tile.bin"),
      "A replaced removal-control directory was accepted for replay.");
  return passed;
}

} // namespace

int wmain(int argc, wchar_t **argv) {
  const int helper = RunHelperMode(argc, argv);
  if (helper >= 0)
    return helper;

  const std::filesystem::path executable = std::filesystem::absolute(argv[0]);
  const std::wstring run_id = std::to_wstring(GetCurrentProcessId());
  const std::filesystem::path test_root =
      std::filesystem::temp_directory_path() /
      (L"BlackSpiritLifeInstallerNativeTests-" + run_id);
  const std::filesystem::path roaming = test_root / L"Roaming";
  const std::filesystem::path local = test_root / L"Local";
  const std::filesystem::path user = test_root / L"User";
  std::filesystem::create_directories(roaming);
  std::filesystem::create_directories(local);
  std::filesystem::create_directories(user);
  SetEnvironmentVariableW(L"APPDATA", roaming.c_str());
  SetEnvironmentVariableW(L"LOCALAPPDATA", local.c_str());
  SetEnvironmentVariableW(L"USERPROFILE", user.c_str());

  bool passed = true;
  const std::filesystem::path empty_install = test_root / L"Empty Install";
  std::filesystem::create_directories(empty_install);
  passed &= Require(
      bsl::installer::ValidateFreshInstallPath(empty_install.wstring()).valid,
      "A regular empty fixed-drive directory was rejected.");
  passed &= Require(WriteText(empty_install / L"occupied.txt", "occupied"),
                    "The non-empty path fixture could not be written.");
  passed &= Require(
      !bsl::installer::ValidateFreshInstallPath(empty_install.wstring()).valid,
      "A non-empty installation directory was accepted.");
  passed &= Require(
      !bsl::installer::ValidateFreshInstallPath(
           (local / L"BlackSpiritLife.App.Removal").wstring())
           .valid,
      "The durable personal-data removal control root was accepted as an "
      "installation directory.");

  const std::filesystem::path custom_profile =
      test_root / L"Custom Personal Data";
  std::filesystem::create_directories(custom_profile);
  const std::string locator_json =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\",\"applicationDirectory\":\"" +
      JsonEscape(custom_profile.wstring()) + "\"}";
  const std::filesystem::path bootstrap =
      local / L"Black Spirit Life" / L"Bootstrap";
  passed &= Require(
      WriteText(bootstrap / L"personal-data-location.json", locator_json) &&
          WriteText(bootstrap / L"personal-data-location.committed.json",
                    locator_json),
      "Committed custom-location fixtures could not be written.");
  passed &= Require(
      !bsl::installer::ValidateFreshInstallPath(
           (custom_profile / L"Application").wstring())
           .valid,
      "An install destination overlapping custom personal data was accepted.");

  passed &= Require(bsl::installer::CompareSemanticVersions(
                        L"0.1.0-beta.10", L"0.1.0-beta.11") < 0 &&
                        bsl::installer::CompareSemanticVersions(
                            L"0.1.0-beta.11", L"0.1.0-beta.11") == 0 &&
                        bsl::installer::CompareSemanticVersions(
                            L"0.1.0", L"0.1.0-beta.11") > 0,
                    "Semantic-version ordering was incorrect.");

  {
    bsl::windows::BetaMaintenanceGate parent_gate;
    std::wstring error;
    passed &= Require(parent_gate.TryAcquire(&error),
                      "The maintenance gate could not be acquired.");
    passed &= Require(RunChild(executable, L"--try-gate") == 23,
                      "A second process entered the held maintenance gate.");
    parent_gate.Release();
    passed &= Require(RunChild(executable, L"--try-gate") == 0,
                      "The maintenance gate was not reusable after release.");
  }

  const std::filesystem::path running_root = test_root / L"Installed App";
  const std::filesystem::path running_current = running_root / L"current";
  std::filesystem::create_directories(running_current);
  const std::string installed_manifest =
      "<package><metadata><id>BlackSpiritLife.App</id>"
      "<channel>win-x64-stable</channel>"
      "<mainExe>BlackSpiritLife.exe</mainExe>"
      "<version>0.1.0</version></metadata></package>";
  passed &= Require(
      WriteText(running_root / L"Update.exe", "MZ") &&
          WriteText(running_root / L"BlackSpiritLife.exe", "MZ") &&
          WriteText(running_current / L"BlackSpiritLife.exe", "MZ") &&
          WriteText(running_current / L"BlackSpiritLifeUpdater.exe",
                    "MZ") &&
          WriteText(running_current / L"sq.version", installed_manifest),
      "The installed-root verification fixture could not be written.");
  bsl::installer::InstalledBeta verified_installation;
  std::wstring verification_error;
  passed &= Require(bsl::installer::VerifyInstalledBetaRoot(
                        running_root.wstring(), &verified_installation,
                        &verification_error) &&
                        verified_installation.version == L"0.1.0" &&
                        verified_installation.root_volume_serial != 0,
                    "A complete fixed-drive application root was not verified.");
  passed &= Require(
      bsl::installer::ValidateInstallRootPersonalDataSafety(
          running_root.wstring())
          .valid,
      "A separate committed personal-data profile blocked Update/Repair.");
  const std::filesystem::path legacy_nested_profile =
      running_root / L"Personal Data";
  std::filesystem::create_directories(legacy_nested_profile);
  const std::string nested_locator_json =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\",\"applicationDirectory\":\"" +
      JsonEscape(legacy_nested_profile.wstring()) + "\"}";
  passed &= Require(
      WriteText(bootstrap / L"personal-data-location.json",
                nested_locator_json) &&
          WriteText(bootstrap / L"personal-data-location.committed.json",
                    nested_locator_json) &&
          !bsl::installer::ValidateInstallRootPersonalDataSafety(
               running_root.wstring())
               .valid,
      "Update/Repair accepted an installation containing personal data.");
  const std::wstring short_running_root = ShortPathIfAvailable(running_root);
  if (!short_running_root.empty()) {
    passed &= Require(
        !bsl::installer::ValidateInstallRootPersonalDataSafety(
             short_running_root)
             .valid,
        "An 8.3 alias bypassed the installation/personal-data overlap guard.");
  }
  passed &= Require(
      WriteText(bootstrap / L"personal-data-location.json", locator_json) &&
          WriteText(bootstrap / L"personal-data-location.committed.json",
                    locator_json),
      "The external committed personal-data fixture could not be restored.");
  const std::string move_journal_json =
      "{\"schemaVersion\":1,\"packageId\":\"BlackSpiritLife.App\","
      "\"releaseChannel\":\"win-x64-stable\","
      "\"phase\":\"destinationPromoted\",\"profileId\":\"profile-test\","
      "\"transactionId\":\"move-test\",\"sourcePath\":\"" +
      JsonEscape(custom_profile.wstring()) + "\",\"destinationPath\":\"" +
      JsonEscape(legacy_nested_profile.wstring()) +
      "\",\"stagingPath\":null,\"destinationExistedEmpty\":false}";
  passed &= Require(
      WriteText(bootstrap / L"personal-data-move-journal.json",
                move_journal_json) &&
          !bsl::installer::ValidateInstallRootPersonalDataSafety(
               running_root.wstring())
               .valid,
      "Update/Repair ignored a pending personal-data move into its root.");
  const std::filesystem::path updater =
      running_current / L"BlackSpiritLifeUpdater.exe";
  const std::filesystem::path parked_updater =
      running_current / L"BlackSpiritLifeUpdater.exe.missing";
  std::filesystem::rename(updater, parked_updater);
  passed &= Require(!bsl::installer::VerifyInstalledBetaRoot(
                        running_root.wstring(), nullptr, &verification_error),
                    "An incomplete installed application root was accepted.");
  std::filesystem::rename(parked_updater, updater);
  const std::filesystem::path copied_process =
      running_current / L"BlackSpiritLife.exe";
  std::filesystem::copy_file(executable, copied_process,
                             std::filesystem::copy_options::overwrite_existing);
  const std::wstring ready_name =
      L"Local\\BlackSpiritLifeInstallerNativeReady-" + run_id;
  const std::wstring stop_name =
      L"Local\\BlackSpiritLifeInstallerNativeStop-" + run_id;
  HANDLE ready_event = CreateEventW(nullptr, TRUE, FALSE, ready_name.c_str());
  HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, stop_name.c_str());
  std::wstring command = Quote(copied_process.wstring()) + L" --wait-events " +
                         Quote(ready_name) + L" " + Quote(stop_name);
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION child{};
  const bool child_started =
      CreateProcessW(copied_process.c_str(), mutable_command.data(), nullptr,
                     nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                     &startup, &child) != FALSE;
  passed &=
      Require(child_started, "The running-process fixture did not start.");
  if (child_started) {
    passed &= Require(WaitForSingleObject(ready_event, 5000) == WAIT_OBJECT_0,
                      "The running-process fixture did not become ready.");
    std::wstring process_error;
    passed &=
        Require(!bsl::installer::EnsureNoRunningBetaProcess(
                    running_root.wstring(), &process_error),
                "A running planner beneath the install root was not detected.");
    SetEvent(stop_event);
    WaitForSingleObject(child.hProcess, 5000);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    passed &=
        Require(bsl::installer::EnsureNoRunningBetaProcess(
                    running_root.wstring(), &process_error),
                "The process guard stayed blocked after the planner exited.");
  }
  if (ready_event != nullptr)
    CloseHandle(ready_event);
  if (stop_event != nullptr)
    CloseHandle(stop_event);

  const std::filesystem::path portable_process =
      test_root / L"Portable" / L"BlackSpiritLife.exe";
  std::filesystem::create_directories(portable_process.parent_path());
  std::filesystem::copy_file(executable, portable_process,
                             std::filesystem::copy_options::overwrite_existing);
  const std::wstring portable_ready_name =
      L"Local\\BlackSpiritLifeInstallerPortableReady-" + run_id;
  const std::wstring portable_stop_name =
      L"Local\\BlackSpiritLifeInstallerPortableStop-" + run_id;
  HANDLE portable_ready =
      CreateEventW(nullptr, TRUE, FALSE, portable_ready_name.c_str());
  HANDLE portable_stop =
      CreateEventW(nullptr, TRUE, FALSE, portable_stop_name.c_str());
  std::wstring portable_command =
      Quote(portable_process.wstring()) + L" --wait-events " +
      Quote(portable_ready_name) + L" " + Quote(portable_stop_name);
  std::vector<wchar_t> mutable_portable_command(portable_command.begin(),
                                                portable_command.end());
  mutable_portable_command.push_back(L'\0');
  STARTUPINFOW portable_startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION portable_child{};
  const bool portable_started =
      CreateProcessW(portable_process.c_str(), mutable_portable_command.data(),
                     nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                     nullptr, &portable_startup, &portable_child) != FALSE;
  passed &= Require(portable_started,
                    "The portable planner process fixture did not start.");
  if (portable_started) {
    passed &=
        Require(WaitForSingleObject(portable_ready, 5000) == WAIT_OBJECT_0,
                "The portable planner process fixture did not become ready.");
    std::wstring process_error;
    passed &= Require(
        !bsl::installer::EnsureNoRunningBetaProcess(running_root.wstring(),
                                                    &process_error),
        "A portable application process outside the install root was not blocked.");
    SetEvent(portable_stop);
    WaitForSingleObject(portable_child.hProcess, 5000);
    CloseHandle(portable_child.hThread);
    CloseHandle(portable_child.hProcess);
  }
  if (portable_ready != nullptr)
    CloseHandle(portable_ready);
  if (portable_stop != nullptr)
    CloseHandle(portable_stop);

  passed &= RunPersonalDataRemovalTests(test_root);

  std::wcout << L"Native installer test artifacts retained at "
             << test_root.wstring() << L'\n';
  return passed ? 0 : 1;
}
