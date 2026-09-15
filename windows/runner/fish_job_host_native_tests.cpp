#include <windows.h>

#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cwchar>
#include <iterator>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

class UniqueHandle {
public:
  UniqueHandle() = default;
  explicit UniqueHandle(HANDLE handle) : handle_(handle) {}
  ~UniqueHandle() { Reset(); }

  UniqueHandle(const UniqueHandle &) = delete;
  UniqueHandle &operator=(const UniqueHandle &) = delete;
  UniqueHandle(UniqueHandle &&other) noexcept
      : handle_(std::exchange(other.handle_, nullptr)) {}
  UniqueHandle &operator=(UniqueHandle &&other) noexcept {
    if (this != &other) {
      Reset(std::exchange(other.handle_, nullptr));
    }
    return *this;
  }

  HANDLE Get() const { return handle_; }
  explicit operator bool() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }
  void Reset(HANDLE handle = nullptr) {
    if (*this) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }

private:
  HANDLE handle_ = nullptr;
};

struct SpawnedProcess {
  UniqueHandle process;
  UniqueHandle thread;
  DWORD process_id = 0;
};

std::wstring CurrentExecutable() {
  std::wstring path(32768, L'\0');
  const DWORD written = GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (written == 0 || written >= path.size()) {
    return {};
  }
  path.resize(written);
  return path;
}

std::wstring ExecutableDirectory(const std::wstring &path) {
  const std::size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : path.substr(0, separator);
}

std::wstring Quote(const std::wstring &argument) {
  std::wstring result(L"\"");
  std::size_t slashes = 0;
  for (const wchar_t character : argument) {
    if (character == L'\\') {
      ++slashes;
    } else if (character == L'"') {
      result.append(slashes * 2 + 1, L'\\');
      result.push_back(L'"');
      slashes = 0;
    } else {
      result.append(slashes, L'\\');
      slashes = 0;
      result.push_back(character);
    }
  }
  result.append(slashes * 2, L'\\');
  result.push_back(L'"');
  return result;
}

std::vector<wchar_t> CommandLine(const std::wstring &executable,
                                 const std::vector<std::wstring> &arguments) {
  std::wstring joined = Quote(executable);
  for (const auto &argument : arguments) {
    joined.push_back(L' ');
    joined.append(Quote(argument));
  }
  std::vector<wchar_t> result(joined.begin(), joined.end());
  result.push_back(L'\0');
  return result;
}

bool Spawn(const std::wstring &executable,
           const std::vector<std::wstring> &arguments, bool inherit_handles,
           STARTUPINFOW *startup, SpawnedProcess *spawned) {
  if (spawned == nullptr) {
    return false;
  }
  STARTUPINFOW default_startup{};
  default_startup.cb = sizeof(default_startup);
  if (startup == nullptr) {
    startup = &default_startup;
  }
  std::vector<wchar_t> command_line = CommandLine(executable, arguments);
  PROCESS_INFORMATION information{};
  if (!CreateProcessW(executable.c_str(), command_line.data(), nullptr, nullptr,
                      inherit_handles ? TRUE : FALSE,
                      CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr,
                      nullptr, startup, &information)) {
    return false;
  }
  spawned->process.Reset(information.hProcess);
  spawned->thread.Reset(information.hThread);
  spawned->process_id = information.dwProcessId;
  return true;
}

bool Require(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s (Windows error %lu)\n", message,
                 static_cast<unsigned long>(GetLastError()));
  }
  return condition;
}

bool WaitExited(HANDLE process, DWORD timeout, DWORD *exit_code = nullptr) {
  if (WaitForSingleObject(process, timeout) != WAIT_OBJECT_0) {
    return false;
  }
  DWORD code = STILL_ACTIVE;
  if (!GetExitCodeProcess(process, &code)) {
    return false;
  }
  if (exit_code != nullptr) {
    *exit_code = code;
  }
  return true;
}

bool WriteRepeated(HANDLE handle, char value, std::size_t byte_count) {
  const std::string block(16384, value);
  std::size_t remaining = byte_count;
  while (remaining != 0) {
    const DWORD requested = static_cast<DWORD>(
        remaining < block.size() ? remaining : block.size());
    DWORD written = 0;
    if (!WriteFile(handle, block.data(), requested, &written, nullptr) ||
        written != requested) {
      return false;
    }
    remaining -= written;
  }
  return true;
}

std::string ReadAll(HANDLE handle) {
  std::string result;
  char buffer[256];
  for (;;) {
    DWORD read = 0;
    if (!ReadFile(handle, buffer, sizeof(buffer), &read, nullptr) || read == 0) {
      break;
    }
    result.append(buffer, buffer + read);
  }
  return result;
}

int EchoTarget(int argc, wchar_t **argv) {
  if (argc != 8 || wcscmp(argv[3], L"") != 0 ||
      wcscmp(argv[4], L"space arg") != 0 ||
      wcscmp(argv[5], L"quote\"inside") != 0 ||
      wcscmp(argv[6], L"trail\\") != 0 ||
      wcscmp(argv[7], L"\u685c\u30da\u30bf\u30eb\U0001F338") != 0) {
    return 91;
  }
  wchar_t *end = nullptr;
  const unsigned long long raw_handle = _wcstoui64(argv[2], &end, 10);
  if (end == argv[2] || *end != L'\0') {
    return 92;
  }
  const HANDLE unexpected =
      reinterpret_cast<HANDLE>(static_cast<std::uintptr_t>(raw_handle));
  if (SetEvent(unexpected)) {
    return 93;
  }
  constexpr std::size_t kLargeOutputBytes = 256 * 1024;
  if (!WriteRepeated(GetStdHandle(STD_OUTPUT_HANDLE), 'O', kLargeOutputBytes) ||
      !WriteRepeated(GetStdHandle(STD_ERROR_HANDLE), 'E', kLargeOutputBytes)) {
    return 94;
  }
  return 37;
}

int OwnerTarget(int argc, wchar_t **argv) {
  if (argc != 3) {
    return 95;
  }
  UniqueHandle stop(OpenEventW(SYNCHRONIZE, FALSE, argv[2]));
  if (!stop) {
    return 96;
  }
  return WaitForSingleObject(stop.Get(), INFINITE) == WAIT_OBJECT_0 ? 0 : 97;
}

int DescendantTarget() {
  Sleep(INFINITE);
  return 98;
}

int TreeTarget(int argc, wchar_t **argv) {
  if (argc != 4) {
    return 99;
  }
  const std::wstring executable = CurrentExecutable();
  SpawnedProcess descendant;
  if (executable.empty() ||
      !Spawn(executable, {L"--test-descendant"}, false, nullptr,
             &descendant)) {
    return 100;
  }

  char process_ids[96]{};
  const int length = sprintf_s(
      process_ids, "%lu %lu",
      static_cast<unsigned long>(GetCurrentProcessId()),
      static_cast<unsigned long>(descendant.process_id));
  UniqueHandle output(CreateFileW(argv[2], GENERIC_WRITE, 0, nullptr,
                                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                                  nullptr));
  DWORD written = 0;
  if (!output || length <= 0 ||
      !WriteFile(output.Get(), process_ids, static_cast<DWORD>(length), &written,
                 nullptr) ||
      written != static_cast<DWORD>(length) || !FlushFileBuffers(output.Get())) {
    TerminateProcess(descendant.process.Get(), 101);
    return 101;
  }
  output.Reset();

  UniqueHandle ready(OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[3]));
  if (!ready || !SetEvent(ready.Get())) {
    TerminateProcess(descendant.process.Get(), 102);
    return 102;
  }
  Sleep(INFINITE);
  return 103;
}

int ExitWithDescendantTarget(int argc, wchar_t **argv) {
  if (argc != 5) {
    return 106;
  }
  const std::wstring executable = CurrentExecutable();
  SpawnedProcess descendant;
  if (executable.empty() ||
      !Spawn(executable, {L"--test-descendant"}, false, nullptr,
             &descendant)) {
    return 107;
  }

  char process_id[48]{};
  const int length =
      sprintf_s(process_id, "%lu",
                static_cast<unsigned long>(descendant.process_id));
  UniqueHandle output(CreateFileW(argv[2], GENERIC_WRITE, 0, nullptr,
                                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                                  nullptr));
  DWORD written = 0;
  if (!output || length <= 0 ||
      !WriteFile(output.Get(), process_id, static_cast<DWORD>(length), &written,
                 nullptr) ||
      written != static_cast<DWORD>(length) || !FlushFileBuffers(output.Get())) {
    TerminateProcess(descendant.process.Get(), 108);
    return 108;
  }
  output.Reset();

  UniqueHandle ready(OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[3]));
  UniqueHandle release(OpenEventW(SYNCHRONIZE, FALSE, argv[4]));
  if (!ready || !release || !SetEvent(ready.Get())) {
    TerminateProcess(descendant.process.Get(), 109);
    return 109;
  }
  if (WaitForSingleObject(release.Get(), 10000) != WAIT_OBJECT_0) {
    TerminateProcess(descendant.process.Get(), 110);
    return 110;
  }
  return 73;
}

bool CreatePipePair(UniqueHandle *read_end, UniqueHandle *write_end) {
  SECURITY_ATTRIBUTES attributes{};
  attributes.nLength = sizeof(attributes);
  attributes.bInheritHandle = TRUE;
  HANDLE raw_read = nullptr;
  HANDLE raw_write = nullptr;
  if (!CreatePipe(&raw_read, &raw_write, &attributes, 0)) {
    return false;
  }
  read_end->Reset(raw_read);
  write_end->Reset(raw_write);
  if (!SetHandleInformation(read_end->Get(), HANDLE_FLAG_INHERIT, 0)) {
    return false;
  }
  return true;
}

bool TestExitArgumentsPipesAndHandleRestriction(const std::wstring &host,
                                                const std::wstring &self) {
  UniqueHandle standard_output_read;
  UniqueHandle standard_output_write;
  UniqueHandle standard_error_read;
  UniqueHandle standard_error_write;
  if (!Require(CreatePipePair(&standard_output_read, &standard_output_write),
               "stdout pipe creation failed") ||
      !Require(CreatePipePair(&standard_error_read, &standard_error_write),
               "stderr pipe creation failed")) {
    return false;
  }

  SECURITY_ATTRIBUTES inheritable{};
  inheritable.nLength = sizeof(inheritable);
  inheritable.bInheritHandle = TRUE;
  UniqueHandle unexpected_event(
      CreateEventW(&inheritable, TRUE, FALSE, nullptr));
  UniqueHandle standard_input(
      CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  &inheritable, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!Require(static_cast<bool>(unexpected_event),
               "inheritable sentinel creation failed") ||
      !Require(static_cast<bool>(standard_input), "NUL input creation failed")) {
    return false;
  }

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = standard_input.Get();
  startup.hStdOutput = standard_output_write.Get();
  startup.hStdError = standard_error_write.Get();

  const auto raw_event = reinterpret_cast<std::uintptr_t>(unexpected_event.Get());
  SpawnedProcess process;
  const std::vector<std::wstring> arguments = {
      L"--owner-pid",
      std::to_wstring(GetCurrentProcessId()),
      L"--",
      self,
      L"--test-echo",
      std::to_wstring(raw_event),
      L"",
      L"space arg",
      L"quote\"inside",
      L"trail\\",
      L"\u685c\u30da\u30bf\u30eb\U0001F338",
  };
  if (!Require(Spawn(host, arguments, true, &startup, &process),
               "Fish host launch failed")) {
    return false;
  }
  process.thread.Reset();
  standard_output_write.Reset();
  standard_error_write.Reset();

  std::string output;
  std::string error;
  std::thread output_reader(
      [&]() { output = ReadAll(standard_output_read.Get()); });
  std::thread error_reader(
      [&]() { error = ReadAll(standard_error_read.Get()); });
  DWORD exit_code = STILL_ACTIVE;
  bool passed = Require(WaitExited(process.process.Get(), 10000, &exit_code),
                        "Fish host did not relay target completion");
  output_reader.join();
  error_reader.join();
  passed &= Require(exit_code == 37, "Fish host changed the target exit code");
  constexpr std::size_t kLargeOutputBytes = 256 * 1024;
  passed &= Require(output.size() == kLargeOutputBytes &&
                        output.find_first_not_of('O') == std::string::npos,
                    "Fish host did not preserve the full target stdout pipe");
  passed &= Require(error.size() == kLargeOutputBytes &&
                        error.find_first_not_of('E') == std::string::npos,
                    "Fish host did not preserve the full target stderr pipe");
  passed &= Require(WaitForSingleObject(unexpected_event.Get(), 0) == WAIT_TIMEOUT,
                    "Fish target inherited an unrelated host handle");
  return passed;
}

bool TestStillActiveValueIsRelayed(const std::wstring &host,
                                   const std::wstring &self) {
  SpawnedProcess process;
  const std::vector<std::wstring> arguments = {
      L"--owner-pid", std::to_wstring(GetCurrentProcessId()), L"--", self,
      L"--test-exit-still-active"};
  if (!Require(Spawn(host, arguments, false, nullptr, &process),
               "STILL_ACTIVE exit-code Fish host launch failed")) {
    return false;
  }
  process.thread.Reset();
  DWORD exit_code = 0;
  return Require(WaitExited(process.process.Get(), 5000, &exit_code),
                 "STILL_ACTIVE exit-code target did not complete") &&
         Require(exit_code == STILL_ACTIVE,
                 "Fish host did not relay target exit code 259 exactly");
}

bool ReadProcessIds(const std::wstring &path, DWORD *target, DWORD *descendant) {
  UniqueHandle file(CreateFileW(path.c_str(), GENERIC_READ,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!file) {
    return false;
  }
  char buffer[96]{};
  DWORD read = 0;
  if (!ReadFile(file.Get(), buffer, sizeof(buffer) - 1, &read, nullptr)) {
    return false;
  }
  unsigned long target_value = 0;
  unsigned long descendant_value = 0;
  if (sscanf_s(buffer, "%lu %lu", &target_value, &descendant_value) != 2) {
    return false;
  }
  *target = static_cast<DWORD>(target_value);
  *descendant = static_cast<DWORD>(descendant_value);
  return *target != 0 && *descendant != 0;
}

bool ReadProcessId(const std::wstring &path, DWORD *process_id) {
  UniqueHandle file(CreateFileW(path.c_str(), GENERIC_READ,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!file) {
    return false;
  }
  char buffer[48]{};
  DWORD read = 0;
  if (!ReadFile(file.Get(), buffer, sizeof(buffer) - 1, &read, nullptr)) {
    return false;
  }
  unsigned long value = 0;
  if (sscanf_s(buffer, "%lu", &value) != 1 || value == 0) {
    return false;
  }
  *process_id = static_cast<DWORD>(value);
  return true;
}

bool TestTargetExitDrainsDescendant(const std::wstring &host,
                                    const std::wstring &self) {
  const std::wstring unique =
      std::to_wstring(GetCurrentProcessId()) + L"-target-exit-" +
      std::to_wstring(GetTickCount64());
  const std::wstring ready_name =
      L"Local\\BlackSpiritLifeFishHostTargetExitReady-" + unique;
  const std::wstring release_name =
      L"Local\\BlackSpiritLifeFishHostTargetExitRelease-" + unique;
  UniqueHandle ready(CreateEventW(nullptr, TRUE, FALSE, ready_name.c_str()));
  UniqueHandle release(
      CreateEventW(nullptr, TRUE, FALSE, release_name.c_str()));
  if (!Require(static_cast<bool>(ready),
               "target-exit ready event creation failed") ||
      !Require(static_cast<bool>(release),
               "target-exit release event creation failed")) {
    return false;
  }

  wchar_t temporary_directory[MAX_PATH + 1]{};
  const DWORD temporary_length =
      GetTempPathW(static_cast<DWORD>(std::size(temporary_directory)),
                   temporary_directory);
  if (!Require(temporary_length != 0 &&
                   temporary_length < std::size(temporary_directory),
               "target-exit temporary path resolution failed")) {
    return false;
  }
  const std::wstring process_file =
      std::wstring(temporary_directory) + L"BlackSpiritLifeFishHost-" + unique +
      L".pid";
  DeleteFileW(process_file.c_str());

  SpawnedProcess fish_host;
  const std::vector<std::wstring> arguments = {
      L"--owner-pid",
      std::to_wstring(GetCurrentProcessId()),
      L"--",
      self,
      L"--test-exit-with-descendant",
      process_file,
      ready_name,
      release_name,
  };
  if (!Require(Spawn(host, arguments, false, nullptr, &fish_host),
               "target-exit Fish host launch failed")) {
    return false;
  }
  fish_host.thread.Reset();

  bool passed = Require(WaitForSingleObject(ready.Get(), 10000) ==
                            WAIT_OBJECT_0,
                        "target-exit descendant did not become ready");
  DWORD descendant_process_id = 0;
  passed &= Require(ReadProcessId(process_file, &descendant_process_id),
                    "target-exit descendant PID could not be read");
  UniqueHandle descendant_process(
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  descendant_process_id));
  passed &= Require(static_cast<bool>(descendant_process),
                    "target-exit descendant could not be opened");
  passed &= Require(WaitForSingleObject(fish_host.process.Get(), 0) ==
                        WAIT_TIMEOUT,
                    "Fish host exited before its direct target was released");

  SetEvent(release.Get());
  DWORD host_exit_code = STILL_ACTIVE;
  passed &= Require(WaitExited(fish_host.process.Get(), 10000, &host_exit_code),
                    "Fish host did not finish after direct target exit");
  passed &= Require(host_exit_code == 73,
                    "Fish host changed the direct target exit code");
  if (descendant_process) {
    passed &= Require(WaitForSingleObject(descendant_process.Get(), 0) ==
                          WAIT_OBJECT_0,
                      "Fish host certified exit before its descendant stopped");
  }

  if (WaitForSingleObject(fish_host.process.Get(), 0) == WAIT_TIMEOUT) {
    TerminateProcess(fish_host.process.Get(), 111);
    WaitForSingleObject(fish_host.process.Get(), 5000);
  }
  DeleteFileW(process_file.c_str());
  return passed;
}

bool TestOwnerExitKillsDescendants(const std::wstring &host,
                                   const std::wstring &self) {
  const std::wstring unique =
      std::to_wstring(GetCurrentProcessId()) + L"-" +
      std::to_wstring(GetTickCount64());
  const std::wstring owner_stop_name =
      L"Local\\BlackSpiritLifeFishHostOwnerStop-" + unique;
  const std::wstring tree_ready_name =
      L"Local\\BlackSpiritLifeFishHostTreeReady-" + unique;
  UniqueHandle owner_stop(
      CreateEventW(nullptr, TRUE, FALSE, owner_stop_name.c_str()));
  UniqueHandle tree_ready(
      CreateEventW(nullptr, TRUE, FALSE, tree_ready_name.c_str()));
  if (!Require(static_cast<bool>(owner_stop), "owner event creation failed") ||
      !Require(static_cast<bool>(tree_ready), "tree event creation failed")) {
    return false;
  }

  wchar_t temporary_directory[MAX_PATH + 1]{};
  const DWORD temporary_length =
      GetTempPathW(static_cast<DWORD>(std::size(temporary_directory)),
                   temporary_directory);
  if (!Require(temporary_length != 0 &&
                   temporary_length < std::size(temporary_directory),
               "temporary path resolution failed")) {
    return false;
  }
  const std::wstring process_file =
      std::wstring(temporary_directory) + L"BlackSpiritLifeFishHost-" + unique +
      L".pids";
  DeleteFileW(process_file.c_str());

  SpawnedProcess owner;
  if (!Require(Spawn(self, {L"--test-owner", owner_stop_name}, false, nullptr,
                     &owner),
               "owner helper launch failed")) {
    return false;
  }
  owner.thread.Reset();

  SpawnedProcess fish_host;
  const std::vector<std::wstring> arguments = {
      L"--owner-pid", std::to_wstring(owner.process_id), L"--", self,
      L"--test-tree", process_file, tree_ready_name};
  if (!Require(Spawn(host, arguments, false, nullptr, &fish_host),
               "tree Fish host launch failed")) {
    SetEvent(owner_stop.Get());
    WaitForSingleObject(owner.process.Get(), 5000);
    return false;
  }
  fish_host.thread.Reset();

  bool passed = Require(WaitForSingleObject(tree_ready.Get(), 10000) ==
                            WAIT_OBJECT_0,
                        "contained target tree did not become ready");
  DWORD target_process_id = 0;
  DWORD descendant_process_id = 0;
  passed &= Require(ReadProcessIds(process_file, &target_process_id,
                                   &descendant_process_id),
                    "contained process IDs could not be read");
  UniqueHandle target_process(
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  target_process_id));
  UniqueHandle descendant_process(
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  descendant_process_id));
  passed &= Require(static_cast<bool>(target_process),
                    "contained target process could not be opened");
  passed &= Require(static_cast<bool>(descendant_process),
                    "contained descendant process could not be opened");

  SetEvent(owner_stop.Get());
  passed &= Require(WaitExited(owner.process.Get(), 5000),
                    "owner helper did not exit");
  DWORD host_exit_code = STILL_ACTIVE;
  passed &= Require(WaitExited(fish_host.process.Get(), 10000, &host_exit_code),
                    "Fish host did not stop when its owner exited");
  passed &= Require(host_exit_code == ERROR_PROCESS_ABORTED,
                    "Fish host reported the wrong owner-exit status");
  if (target_process) {
    passed &= Require(WaitForSingleObject(target_process.Get(), 5000) ==
                          WAIT_OBJECT_0,
                      "owner exit did not terminate the direct target");
  }
  if (descendant_process) {
    passed &= Require(WaitForSingleObject(descendant_process.Get(), 5000) ==
                          WAIT_OBJECT_0,
                      "owner exit did not terminate the target descendant");
  }

  if (WaitForSingleObject(fish_host.process.Get(), 0) == WAIT_TIMEOUT) {
    TerminateProcess(fish_host.process.Get(), 104);
    WaitForSingleObject(fish_host.process.Get(), 5000);
  }
  if (WaitForSingleObject(owner.process.Get(), 0) == WAIT_TIMEOUT) {
    TerminateProcess(owner.process.Get(), 105);
    WaitForSingleObject(owner.process.Get(), 5000);
  }
  DeleteFileW(process_file.c_str());
  return passed;
}

bool TestHostTerminationKillsDescendants(const std::wstring &host,
                                         const std::wstring &self) {
  const std::wstring unique =
      std::to_wstring(GetCurrentProcessId()) + L"-kill-" +
      std::to_wstring(GetTickCount64());
  const std::wstring tree_ready_name =
      L"Local\\BlackSpiritLifeFishHostKillReady-" + unique;
  UniqueHandle tree_ready(
      CreateEventW(nullptr, TRUE, FALSE, tree_ready_name.c_str()));
  if (!Require(static_cast<bool>(tree_ready),
               "host-kill tree event creation failed")) {
    return false;
  }

  wchar_t temporary_directory[MAX_PATH + 1]{};
  const DWORD temporary_length =
      GetTempPathW(static_cast<DWORD>(std::size(temporary_directory)),
                   temporary_directory);
  if (!Require(temporary_length != 0 &&
                   temporary_length < std::size(temporary_directory),
               "host-kill temporary path resolution failed")) {
    return false;
  }
  const std::wstring process_file =
      std::wstring(temporary_directory) + L"BlackSpiritLifeFishHost-" + unique +
      L".pids";
  DeleteFileW(process_file.c_str());

  SpawnedProcess fish_host;
  const std::vector<std::wstring> arguments = {
      L"--owner-pid", std::to_wstring(GetCurrentProcessId()), L"--", self,
      L"--test-tree", process_file, tree_ready_name};
  if (!Require(Spawn(host, arguments, false, nullptr, &fish_host),
               "host-kill Fish host launch failed")) {
    return false;
  }
  fish_host.thread.Reset();

  bool passed = Require(WaitForSingleObject(tree_ready.Get(), 10000) ==
                            WAIT_OBJECT_0,
                        "host-kill target tree did not become ready");
  DWORD target_process_id = 0;
  DWORD descendant_process_id = 0;
  passed &= Require(ReadProcessIds(process_file, &target_process_id,
                                   &descendant_process_id),
                    "host-kill process IDs could not be read");
  UniqueHandle target_process(
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  target_process_id));
  UniqueHandle descendant_process(
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  descendant_process_id));
  passed &= Require(static_cast<bool>(target_process),
                    "host-kill direct target could not be opened");
  passed &= Require(static_cast<bool>(descendant_process),
                    "host-kill descendant could not be opened");

  constexpr DWORD kForcedHostExit = 211;
  passed &= Require(TerminateProcess(fish_host.process.Get(), kForcedHostExit) !=
                        FALSE,
                    "Fish host could not be force-terminated");
  DWORD host_exit_code = STILL_ACTIVE;
  passed &= Require(WaitExited(fish_host.process.Get(), 5000, &host_exit_code),
                    "force-terminated Fish host did not exit");
  passed &= Require(host_exit_code == kForcedHostExit,
                    "force-terminated Fish host exit status changed");
  if (target_process) {
    passed &= Require(WaitForSingleObject(target_process.Get(), 5000) ==
                          WAIT_OBJECT_0,
                      "Fish host termination did not kill the direct target");
  }
  if (descendant_process) {
    passed &= Require(WaitForSingleObject(descendant_process.Get(), 5000) ==
                          WAIT_OBJECT_0,
                      "Fish host termination did not kill the descendant");
  }

  if (WaitForSingleObject(fish_host.process.Get(), 0) == WAIT_TIMEOUT) {
    TerminateProcess(fish_host.process.Get(), 212);
    WaitForSingleObject(fish_host.process.Get(), 5000);
  }
  DeleteFileW(process_file.c_str());
  return passed;
}

} // namespace

int wmain(int argc, wchar_t **argv) {
  if (argc >= 2 && wcscmp(argv[1], L"--test-echo") == 0) {
    return EchoTarget(argc, argv);
  }
  if (argc >= 2 && wcscmp(argv[1], L"--test-owner") == 0) {
    return OwnerTarget(argc, argv);
  }
  if (argc == 2 && wcscmp(argv[1], L"--test-descendant") == 0) {
    return DescendantTarget();
  }
  if (argc == 2 && wcscmp(argv[1], L"--test-exit-still-active") == 0) {
    return static_cast<int>(STILL_ACTIVE);
  }
  if (argc >= 2 && wcscmp(argv[1], L"--test-tree") == 0) {
    return TreeTarget(argc, argv);
  }
  if (argc >= 2 && wcscmp(argv[1], L"--test-exit-with-descendant") == 0) {
    return ExitWithDescendantTarget(argc, argv);
  }

  const std::wstring self = CurrentExecutable();
  const std::wstring host =
      ExecutableDirectory(self) + L"\\BlackSpiritLifeFishHost.exe";
  bool passed = Require(!self.empty(), "test executable path is unavailable") &&
                Require(GetFileAttributesW(host.c_str()) !=
                            INVALID_FILE_ATTRIBUTES,
                        "Fish host executable is unavailable");
  if (passed) {
    passed &= TestExitArgumentsPipesAndHandleRestriction(host, self);
    passed &= TestStillActiveValueIsRelayed(host, self);
    passed &= TestTargetExitDrainsDescendant(host, self);
    passed &= TestOwnerExitKillsDescendants(host, self);
    passed &= TestHostTerminationKillsDescendants(host, self);
  }
  if (passed) {
    std::puts("BlackSpiritLifeFishHost native integration checks passed.");
  }
  return passed ? 0 : 1;
}
