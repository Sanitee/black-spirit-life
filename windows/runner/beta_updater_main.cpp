#include <windows.h>
#include <shellapi.h>
#include <wininet.h>

#include <Velopack.h>

#include "../shared/beta_maintenance_gate.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr std::array<std::uint8_t, 8> kProtocolMagic = {'B', 'S', 'L', 'U',
                                                        'P', 'D', '1', 0};
constexpr std::uint32_t kProtocolVersion = 1;
constexpr char kPackageId[] = "BlackSpiritLife.App";
constexpr char kChannel[] = "win-x64-stable";
constexpr wchar_t kMainExecutable[] = L"BlackSpiritLife.exe";
constexpr std::size_t kMaximumRequestBytes = 64 * 1024;
constexpr std::size_t kMaximumSourceBytes = 16 * 1024;
constexpr std::size_t kMaximumTextBytes = 64 * 1024;

enum class Operation : std::uint32_t {
  kStatus = 1,
  kCheck = 2,
  kDownload = 3,
  kPrepareApply = 4,
};

struct Request {
  Operation operation = Operation::kStatus;
  std::uint32_t planner_pid = 0;
  std::string source;
  std::string package_id;
  std::string channel;
  std::string current_version;
  std::string target_version;
};

struct Snapshot {
  std::string status = "idle";
  bool installed = false;
  bool portable = true;
  std::string current_version;
  std::string app_id;
  std::string target_version;
  std::string release_notes_markdown;
  std::uint64_t download_size_bytes = 0;
  std::uint64_t full_size_bytes = 0;
  std::uint32_t delta_count = 0;
  double progress = 0;
  std::string message;
};

std::string SafeString(const char *value) {
  return value == nullptr ? std::string() : std::string(value);
}

std::string BoundedText(const char *value) {
  const std::string text = SafeString(value);
  if (text.size() <= kMaximumTextBytes)
    return text;
  return "Release notes are too large to display in the updater.";
}

std::string JsonEscape(const std::string &value) {
  std::ostringstream output;
  for (const unsigned char byte : value) {
    switch (byte) {
    case '"':
      output << "\\\"";
      break;
    case '\\':
      output << "\\\\";
      break;
    case '\b':
      output << "\\b";
      break;
    case '\f':
      output << "\\f";
      break;
    case '\n':
      output << "\\n";
      break;
    case '\r':
      output << "\\r";
      break;
    case '\t':
      output << "\\t";
      break;
    default:
      if (byte < 0x20) {
        constexpr char hex[] = "0123456789abcdef";
        output << "\\u00" << hex[(byte >> 4) & 0xf] << hex[byte & 0xf];
      } else {
        output << static_cast<char>(byte);
      }
      break;
    }
  }
  return output.str();
}

bool WriteHandle(HANDLE output, const std::string &value) {
  if (output == nullptr || output == INVALID_HANDLE_VALUE)
    return false;
  std::size_t offset = 0;
  while (offset < value.size()) {
    const DWORD remaining = static_cast<DWORD>(std::min<std::size_t>(
        value.size() - offset, std::numeric_limits<DWORD>::max()));
    DWORD written = 0;
    if (WriteFile(output, value.data() + offset, remaining, &written,
                  nullptr) == FALSE ||
        written == 0) {
      return false;
    }
    offset += written;
  }
  return true;
}

bool WriteStdout(const std::string &value) {
  return WriteHandle(GetStdHandle(STD_OUTPUT_HANDLE), value);
}

void WriteDiagnostic(const std::string &value) {
  WriteHandle(GetStdHandle(STD_ERROR_HANDLE), value + "\n");
}

void VelopackLog(void *, const char *level, const char *message) {
  WriteDiagnostic("[velopack:" + SafeString(level) + "] " +
                  SafeString(message));
}

void Emit(const Snapshot &snapshot) {
  std::ostringstream json;
  json << "{\"protocolVersion\":" << kProtocolVersion << ",\"status\":\""
       << JsonEscape(snapshot.status) << "\""
       << ",\"installed\":" << (snapshot.installed ? "true" : "false")
       << ",\"portable\":" << (snapshot.portable ? "true" : "false")
       << ",\"currentVersion\":\"" << JsonEscape(snapshot.current_version)
       << "\""
       << ",\"appId\":\"" << JsonEscape(snapshot.app_id) << "\""
       << ",\"targetVersion\":\"" << JsonEscape(snapshot.target_version) << "\""
       << ",\"releaseNotesMarkdown\":\""
       << JsonEscape(snapshot.release_notes_markdown) << "\""
       << ",\"downloadSizeBytes\":" << snapshot.download_size_bytes
       << ",\"fullSizeBytes\":" << snapshot.full_size_bytes
       << ",\"deltaCount\":" << snapshot.delta_count
       << ",\"progress\":" << snapshot.progress << ",\"message\":\""
       << JsonEscape(snapshot.message) << "\"}\n";
  WriteStdout(json.str());
}

int EmitError(const std::string &message) {
  Snapshot snapshot;
  snapshot.status = "error";
  snapshot.message = message;
  Emit(snapshot);
  return 0;
}

std::string LastVelopackError() {
  // Velopack 1.2.0's return_cstr writes one terminator byte beyond the
  // logical capacity supplied by the caller. Keep that byte inside a private
  // guard while continuing to advertise only the documented capacity.
  std::size_t logical_capacity = 1024;
  std::vector<char> buffer(logical_capacity + 1, '\0');
  const std::size_t required =
      vpkc_get_last_error(buffer.data(), logical_capacity);
  if (required > logical_capacity && required <= kMaximumTextBytes) {
    logical_capacity = required;
    buffer.assign(logical_capacity + 1, '\0');
    vpkc_get_last_error(buffer.data(), logical_capacity);
  }
  const std::string message(buffer.data());
  return message.empty() ? "Velopack did not provide an error message."
                         : message;
}

std::string ManagerString(vpkc_update_manager_t *manager, bool app_id) {
  const std::size_t required =
      app_id ? vpkc_get_app_id(manager, nullptr, 0)
             : vpkc_get_current_version(manager, nullptr, 0);
  if (required == 0 || required > 4096)
    return std::string();
  // The pinned Velopack runtime reports the string length without its
  // terminator, then writes the terminator at [required]. Provide a physical
  // guard byte without increasing the logical capacity passed across the ABI.
  std::vector<char> buffer(required + 1, '\0');
  if (app_id) {
    vpkc_get_app_id(manager, buffer.data(), required);
  } else {
    vpkc_get_current_version(manager, buffer.data(), required);
  }
  return std::string(buffer.data());
}

bool IsRemoteSource(const std::string &source) {
  return source.rfind("https://", 0) == 0 || source.rfind("http://", 0) == 0;
}

bool IsGithubRepositorySource(const std::string &source) {
  constexpr char kGithubPrefix[] = "https://github.com/";
  if (source.rfind(kGithubPrefix, 0) != 0)
    return false;

  const std::string repository = source.substr(sizeof(kGithubPrefix) - 1);
  const std::size_t separator = repository.find('/');
  return separator != std::string::npos && separator > 0 &&
         separator + 1 < repository.size() &&
         repository.find('/', separator + 1) == std::string::npos &&
         repository.find_first_of("?#") == std::string::npos;
}

std::string FailureStatus(const std::string &source) {
  DWORD flags = 0;
  if (IsRemoteSource(source) && InternetGetConnectedState(&flags, 0) == FALSE) {
    return "offline";
  }
  return "error";
}

bool ReadBytes(const std::wstring &path, std::vector<std::uint8_t> *output) {
  if (output == nullptr)
    return false;
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream)
    return false;
  const std::streamoff length = stream.tellg();
  if (length < 0 || static_cast<std::uint64_t>(length) > kMaximumRequestBytes) {
    return false;
  }
  stream.seekg(0, std::ios::beg);
  output->resize(static_cast<std::size_t>(length));
  if (!output->empty()) {
    stream.read(reinterpret_cast<char *>(output->data()), length);
  }
  return stream.good() || stream.eof();
}

bool ReadU32(const std::vector<std::uint8_t> &bytes, std::size_t *offset,
             std::uint32_t *value) {
  if (offset == nullptr || value == nullptr || *offset > bytes.size() ||
      bytes.size() - *offset < 4) {
    return false;
  }
  const std::size_t index = *offset;
  *value = static_cast<std::uint32_t>(bytes[index]) |
           (static_cast<std::uint32_t>(bytes[index + 1]) << 8) |
           (static_cast<std::uint32_t>(bytes[index + 2]) << 16) |
           (static_cast<std::uint32_t>(bytes[index + 3]) << 24);
  *offset += 4;
  return true;
}

bool ReadString(const std::vector<std::uint8_t> &bytes, std::size_t *offset,
                std::size_t maximum, std::string *value) {
  std::uint32_t length = 0;
  if (!ReadU32(bytes, offset, &length) || length > maximum ||
      *offset > bytes.size() || bytes.size() - *offset < length) {
    return false;
  }
  value->assign(reinterpret_cast<const char *>(bytes.data() + *offset), length);
  *offset += length;
  return value->find('\0') == std::string::npos;
}

bool DecodeRequest(const std::vector<std::uint8_t> &bytes, Request *request) {
  if (request == nullptr || bytes.size() < kProtocolMagic.size() ||
      !std::equal(kProtocolMagic.begin(), kProtocolMagic.end(),
                  bytes.begin())) {
    return false;
  }
  std::size_t offset = kProtocolMagic.size();
  std::uint32_t version = 0;
  std::uint32_t operation = 0;
  if (!ReadU32(bytes, &offset, &version) || version != kProtocolVersion ||
      !ReadU32(bytes, &offset, &operation) ||
      operation < static_cast<std::uint32_t>(Operation::kStatus) ||
      operation > static_cast<std::uint32_t>(Operation::kPrepareApply) ||
      !ReadU32(bytes, &offset, &request->planner_pid) ||
      !ReadString(bytes, &offset, kMaximumSourceBytes, &request->source) ||
      !ReadString(bytes, &offset, 256, &request->package_id) ||
      !ReadString(bytes, &offset, 128, &request->channel) ||
      !ReadString(bytes, &offset, 128, &request->current_version) ||
      !ReadString(bytes, &offset, 128, &request->target_version) ||
      offset != bytes.size()) {
    return false;
  }
  request->operation = static_cast<Operation>(operation);
  return true;
}

std::wstring FullPath(const std::wstring &path) {
  const DWORD required = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
  if (required == 0)
    return std::wstring();
  std::vector<wchar_t> buffer(required + 1, L'\0');
  const DWORD written = GetFullPathNameW(
      path.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
  if (written == 0 || written >= buffer.size())
    return std::wstring();
  return std::wstring(buffer.data(), written);
}

bool RequestPathIsInTemporaryDirectory(const std::wstring &request_path) {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  DWORD length = GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
  if (length == 0)
    return false;
  if (length >= buffer.size()) {
    buffer.assign(length + 1, L'\0');
    length = GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
    if (length == 0 || length >= buffer.size())
      return false;
  }
  std::wstring temporary = FullPath(std::wstring(buffer.data(), length));
  std::wstring request = FullPath(request_path);
  if (temporary.empty() || request.empty())
    return false;
  if (temporary.back() != L'\\')
    temporary.push_back(L'\\');
  if (request.size() <= temporary.size())
    return false;
  return _wcsnicmp(request.c_str(), temporary.c_str(), temporary.size()) == 0;
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                            static_cast<DWORD>(buffer.size()));
    if (length == 0)
      return std::wstring();
    if (length < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    buffer.assign(buffer.size() * 2, L'\0');
  }
}

std::wstring ParentDirectory(const std::wstring &path) {
  const std::size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : path.substr(0, separator);
}

bool ReadSmallTextFile(const std::wstring &path, std::string *text) {
  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream)
    return false;
  const std::streamoff length = stream.tellg();
  if (length < 0 || length > 128 * 1024)
    return false;
  stream.seekg(0, std::ios::beg);
  text->assign(static_cast<std::size_t>(length), '\0');
  if (!text->empty())
    stream.read(text->data(), length);
  return stream.good() || stream.eof();
}

bool InstalledManifestMatches(const std::wstring &executable_directory) {
  std::string manifest;
  if (!ReadSmallTextFile(executable_directory + L"\\sq.version", &manifest)) {
    return false;
  }
  return manifest.find("<id>BlackSpiritLife.App</id>") !=
             std::string::npos &&
         manifest.find("<channel>win-x64-stable</channel>") !=
             std::string::npos &&
         manifest.find("<mainExe>BlackSpiritLife.exe</mainExe>") !=
             std::string::npos;
}

bool VerifyPlannerProcess(std::uint32_t process_id,
                          const std::wstring &executable_directory,
                          std::string *error) {
  if (process_id == 0 || process_id == GetCurrentProcessId()) {
    *error = "The planner process identity is invalid.";
    return false;
  }
  const HANDLE process = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, process_id);
  if (process == nullptr) {
    *error = "The running planner process could not be verified.";
    return false;
  }
  DWORD exit_code = 0;
  std::vector<wchar_t> path(32768, L'\0');
  DWORD path_length = static_cast<DWORD>(path.size());
  const bool valid = GetExitCodeProcess(process, &exit_code) != FALSE &&
                     exit_code == STILL_ACTIVE &&
                     QueryFullProcessImageNameW(process, 0, path.data(),
                                                &path_length) != FALSE;
  CloseHandle(process);
  if (!valid) {
    *error = "The running planner process could not be verified.";
    return false;
  }
  const std::wstring actual = FullPath(std::wstring(path.data(), path_length));
  const std::wstring expected =
      FullPath(executable_directory + L"\\" + kMainExecutable);
  if (actual.empty() || expected.empty() ||
      _wcsicmp(actual.c_str(), expected.c_str()) != 0) {
    *error = "The update request did not come from this installation.";
    return false;
  }
  return true;
}

bool PrepareSnapshot(vpkc_update_manager_t *manager, const Request &request,
                     Snapshot *snapshot) {
  snapshot->portable = vpkc_is_portable(manager);
  snapshot->installed = !snapshot->portable;
  snapshot->current_version = ManagerString(manager, false);
  snapshot->app_id = ManagerString(manager, true);
  if (snapshot->portable) {
    snapshot->status = "unsupported";
    snapshot->message =
        "Updates are available after Black Spirit Life is installed.";
    return false;
  }
  const std::wstring directory = ParentDirectory(ExecutablePath());
  if (snapshot->app_id != kPackageId || request.package_id != kPackageId ||
      request.channel != kChannel || !InstalledManifestMatches(directory)) {
    snapshot->status = "error";
    snapshot->message =
        "The installed package or update channel did not match.";
    return false;
  }
  if (request.current_version.empty() ||
      snapshot->current_version != request.current_version) {
    snapshot->status = "error";
    snapshot->message =
        "The installed version changed before the update operation.";
    return false;
  }
  return true;
}

void AddUpdateDetails(const vpkc_update_info_t *update, Snapshot *snapshot) {
  if (update == nullptr || update->TargetFullRelease == nullptr)
    return;
  const vpkc_asset_t *target = update->TargetFullRelease;
  snapshot->target_version = SafeString(target->Version);
  snapshot->release_notes_markdown = BoundedText(target->NotesMarkdown);
  snapshot->full_size_bytes = target->Size;
  snapshot->delta_count = static_cast<std::uint32_t>(std::min<std::size_t>(
      update->DeltasToTargetCount, std::numeric_limits<std::uint32_t>::max()));
  std::uint64_t delta_size = 0;
  for (std::size_t index = 0; index < update->DeltasToTargetCount; ++index) {
    const vpkc_asset_t *delta = update->DeltasToTarget[index];
    if (delta == nullptr ||
        delta->Size > std::numeric_limits<std::uint64_t>::max() - delta_size) {
      delta_size = 0;
      break;
    }
    delta_size += delta->Size;
  }
  snapshot->download_size_bytes =
      snapshot->delta_count > 0 && delta_size > 0 ? delta_size : target->Size;
}

bool ValidateUpdate(const Request &request, const vpkc_update_info_t *update,
                    Snapshot *snapshot) {
  if (update == nullptr || update->TargetFullRelease == nullptr) {
    snapshot->status = "error";
    snapshot->message = "The update source returned an incomplete release.";
    return false;
  }
  AddUpdateDetails(update, snapshot);
  if (SafeString(update->TargetFullRelease->PackageId) != kPackageId) {
    snapshot->status = "error";
    snapshot->message = "The available package has the wrong app identity.";
    return false;
  }
  if (update->IsDowngrade) {
    snapshot->status = "error";
    snapshot->message = "Downgrades and lateral updates are blocked.";
    return false;
  }
  if (!request.target_version.empty() &&
      snapshot->target_version != request.target_version) {
    snapshot->status = "error";
    snapshot->message =
        "The available update changed. Check again before downloading.";
    return false;
  }
  return true;
}

void DownloadProgress(void *user_data, std::size_t progress) {
  auto *snapshot = static_cast<Snapshot *>(user_data);
  if (snapshot == nullptr)
    return;
  snapshot->status = "downloading";
  snapshot->progress = std::min<std::size_t>(100, progress) / 100.0;
  snapshot->message = "Downloading the Black Spirit Life update.";
  Emit(*snapshot);
}

int Run(const Request &request) {
  vpkc_set_logger(VelopackLog, nullptr);
  WriteDiagnostic("[helper] validating request");
  if (request.source.empty() || request.source.size() > kMaximumSourceBytes ||
      request.package_id != kPackageId || request.channel != kChannel) {
    return EmitError("The updater request did not match this installation.");
  }

  const std::wstring executable_directory = ParentDirectory(ExecutablePath());
  const std::wstring manifest_path = executable_directory + L"\\sq.version";
  if (GetFileAttributesW(manifest_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    Snapshot portable;
    portable.status = "unsupported";
    portable.message =
        "Updates are available after Black Spirit Life is installed.";
    Emit(portable);
    return 0;
  }
  if (!InstalledManifestMatches(executable_directory)) {
    return EmitError(
        "The installed package or update channel did not match.");
  }

  std::string explicit_channel = kChannel;
  vpkc_update_options_t options{};
  options.AllowVersionDowngrade = false;
  options.ExplicitChannel = explicit_channel.data();
  options.MaximumDeltasBeforeFallback = 10;
  vpkc_update_manager_t *manager = nullptr;
  bool manager_created = false;
  if (IsGithubRepositorySource(request.source)) {
    // Public stable releases use GitHub's provider-specific source. Never
    // embed an access token in a desktop application, and never include
    // prereleases in the Stable channel.
    vpkc_update_source_t *github_source =
        vpkc_new_source_github(request.source.c_str(), nullptr, false);
    if (github_source != nullptr) {
      manager_created = vpkc_new_update_manager_with_source(
          github_source, &options, nullptr, &manager);
    }
  } else {
    // Keep ordinary HTTP and local-directory feeds for isolated update
    // rehearsals without changing their existing behavior.
    manager_created = vpkc_new_update_manager(
        request.source.c_str(), &options, nullptr, &manager);
  }
  if (!manager_created || manager == nullptr) {
    Snapshot failure;
    failure.status = FailureStatus(request.source);
    failure.message = LastVelopackError();
    Emit(failure);
    return 0;
  }
  WriteDiagnostic("[helper] update manager ready");

  // This helper is deliberately short-lived. The operating system reclaims
  // the manager and asset allocations when it exits. Avoiding in-process
  // Velopack teardown also isolates the heap-corruption path observed in
  // Beta 3.
  Snapshot snapshot;
  if (!PrepareSnapshot(manager, request, &snapshot)) {
    Emit(snapshot);
    return 0;
  }
  WriteDiagnostic("[helper] installed identity verified");

  if (request.operation == Operation::kStatus) {
    vpkc_asset_t *pending = nullptr;
    if (vpkc_update_pending_restart(manager, &pending) && pending != nullptr) {
      snapshot.status = "ready";
      snapshot.target_version = SafeString(pending->Version);
      snapshot.full_size_bytes = pending->Size;
      snapshot.download_size_bytes = pending->Size;
      snapshot.progress = 1;
      snapshot.message = "The update is ready to install.";
    } else {
      snapshot.status = "idle";
    }
    Emit(snapshot);
    return 0;
  }

  if (request.operation == Operation::kPrepareApply) {
    vpkc_asset_t *pending = nullptr;
    if (!vpkc_update_pending_restart(manager, &pending) || pending == nullptr) {
      snapshot.status = "error";
      snapshot.message = "No downloaded update is ready to install.";
      Emit(snapshot);
      return 0;
    }
    snapshot.target_version = SafeString(pending->Version);
    if (SafeString(pending->PackageId) != kPackageId ||
        request.target_version.empty() ||
        snapshot.target_version != request.target_version) {
      snapshot.status = "error";
      snapshot.message =
          "The downloaded update no longer matches the expected version.";
      Emit(snapshot);
      return 0;
    }
    std::string process_error;
    const std::wstring directory = ParentDirectory(ExecutablePath());
    if (!VerifyPlannerProcess(request.planner_pid, directory, &process_error)) {
      snapshot.status = "error";
      snapshot.message = process_error;
      Emit(snapshot);
      return 0;
    }
    if (!vpkc_unsafe_apply_updates(manager, pending, true, request.planner_pid,
                                   true, nullptr, 0)) {
      snapshot.status = "error";
      snapshot.message = LastVelopackError();
      Emit(snapshot);
      return 0;
    }
    snapshot.status = "applying";
    snapshot.progress = 1;
    snapshot.message = "Restarting to install the update.";
    Emit(snapshot);
    return 0;
  }

  vpkc_update_info_t *update = nullptr;
  WriteDiagnostic("[helper] checking release feed");
  const vpkc_update_check_t check = vpkc_check_for_updates(manager, &update);
  WriteDiagnostic("[helper] release feed check returned");
  if (check == UPDATE_ERROR) {
    snapshot.status = FailureStatus(request.source);
    snapshot.message = LastVelopackError();
    Emit(snapshot);
    return 0;
  }
  if (check == NO_UPDATE_AVAILABLE || check == REMOTE_IS_EMPTY ||
      update == nullptr || update->TargetFullRelease == nullptr) {
    snapshot.status = "upToDate";
    snapshot.message = check == REMOTE_IS_EMPTY
                           ? "The update source has no newer release yet."
                           : "Black Spirit Life is up to date.";
    Emit(snapshot);
    return 0;
  }
  if (!ValidateUpdate(request, update, &snapshot)) {
    Emit(snapshot);
    return 0;
  }

  if (request.operation == Operation::kCheck) {
    snapshot.status = "available";
    snapshot.message = "A Black Spirit Life update is available.";
    Emit(snapshot);
    return 0;
  }

  snapshot.status = "downloading";
  snapshot.message = "Downloading the Black Spirit Life update.";
  Emit(snapshot);
  if (!vpkc_download_updates(manager, update, DownloadProgress, &snapshot)) {
    snapshot.status = FailureStatus(request.source);
    snapshot.message = LastVelopackError();
    Emit(snapshot);
    return 0;
  }
  snapshot.status = "ready";
  snapshot.progress = 1;
  snapshot.message = "The update is ready to install.";
  Emit(snapshot);
  return 0;
}

} // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t *, int) {
  bsl::windows::BetaMaintenanceGate maintenance_gate;
  std::wstring maintenance_error;
  if (!maintenance_gate.TryAcquire(&maintenance_error)) {
    return EmitError(
        "Black Spirit Life setup is running. Try the update again after "
        "it finishes.");
  }
  int argument_count = 0;
  wchar_t **arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr)
    return EmitError("The updater request is missing.");
  std::wstring request_path;
  for (int index = 1; index + 1 < argument_count; ++index) {
    if (std::wstring(arguments[index]) == L"--request") {
      request_path = arguments[++index];
    }
  }
  LocalFree(arguments);
  if (request_path.empty() ||
      !RequestPathIsInTemporaryDirectory(request_path)) {
    return EmitError("The updater request path is invalid.");
  }
  std::vector<std::uint8_t> bytes;
  Request request;
  if (!ReadBytes(request_path, &bytes) || !DecodeRequest(bytes, &request)) {
    return EmitError("The updater request could not be read safely.");
  }
  return Run(request);
}
