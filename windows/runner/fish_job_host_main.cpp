#include <windows.h>

#include <shellapi.h>

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cwchar>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr DWORD kOwnerExited = ERROR_PROCESS_ABORTED;
constexpr DWORD kJobCleanupFailed = 0xE04A0001;
constexpr ULONGLONG kJobDrainTimeoutMilliseconds = 5000;

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

class AttributeList {
public:
  AttributeList() = default;
  ~AttributeList() { Reset(); }

  AttributeList(const AttributeList &) = delete;
  AttributeList &operator=(const AttributeList &) = delete;

  bool Initialize(DWORD attribute_count) {
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(nullptr, attribute_count, 0, &bytes);
    if (bytes == 0) {
      return false;
    }
    storage_ = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (storage_ == nullptr) {
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return false;
    }
    list_ = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage_);
    if (!InitializeProcThreadAttributeList(list_, attribute_count, 0,
                                           &bytes)) {
      const DWORD error = GetLastError();
      Reset();
      SetLastError(error);
      return false;
    }
    initialized_ = true;
    return true;
  }

  bool Set(DWORD_PTR attribute, void *value, SIZE_T bytes) {
    return UpdateProcThreadAttribute(list_, 0, attribute, value, bytes,
                                     nullptr, nullptr) != FALSE;
  }

  LPPROC_THREAD_ATTRIBUTE_LIST Get() const { return list_; }

private:
  void Reset() {
    if (initialized_ && list_ != nullptr) {
      DeleteProcThreadAttributeList(list_);
    }
    if (storage_ != nullptr) {
      HeapFree(GetProcessHeap(), 0, storage_);
    }
    storage_ = nullptr;
    list_ = nullptr;
    initialized_ = false;
  }

  void *storage_ = nullptr;
  LPPROC_THREAD_ATTRIBUTE_LIST list_ = nullptr;
  bool initialized_ = false;
};

void ReportFailure(const wchar_t *message, DWORD error) {
  wchar_t buffer[512]{};
  const int count = swprintf_s(buffer, L"BlackSpiritLifeFishHost: %ls (%lu)\r\n",
                               message, static_cast<unsigned long>(error));
  if (count <= 0) {
    return;
  }
  const HANDLE output = GetStdHandle(STD_ERROR_HANDLE);
  if (output == nullptr || output == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  WriteFile(output, buffer,
            static_cast<DWORD>(count * static_cast<int>(sizeof(wchar_t))),
            &written, nullptr);
}

bool IsAbsolutePath(const std::wstring &path) {
  if (path.size() >= 3 &&
      ((path[0] >= L'A' && path[0] <= L'Z') ||
       (path[0] >= L'a' && path[0] <= L'z')) &&
      path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) {
    return true;
  }
  return path.size() >= 2 &&
         (path[0] == L'\\' || path[0] == L'/') &&
         (path[1] == L'\\' || path[1] == L'/');
}

bool ParseProcessId(const wchar_t *text, DWORD *process_id) {
  if (text == nullptr || *text == L'\0' || process_id == nullptr) {
    return false;
  }
  wchar_t *end = nullptr;
  errno = 0;
  const unsigned long long parsed = _wcstoui64(text, &end, 10);
  if (errno != 0 || end == text || *end != L'\0' || parsed == 0 ||
      parsed > std::numeric_limits<DWORD>::max()) {
    return false;
  }
  *process_id = static_cast<DWORD>(parsed);
  return true;
}

std::wstring QuoteCommandLineArgument(const std::wstring &argument) {
  std::wstring result;
  result.reserve(argument.size() + 2);
  result.push_back(L'"');
  std::size_t backslashes = 0;
  for (const wchar_t character : argument) {
    if (character == L'\\') {
      ++backslashes;
      continue;
    }
    if (character == L'"') {
      result.append(backslashes * 2 + 1, L'\\');
      result.push_back(L'"');
      backslashes = 0;
      continue;
    }
    result.append(backslashes, L'\\');
    backslashes = 0;
    result.push_back(character);
  }
  result.append(backslashes * 2, L'\\');
  result.push_back(L'"');
  return result;
}

bool BuildCommandLine(int argument_count, wchar_t **arguments,
                      std::vector<wchar_t> *command_line) {
  if (argument_count <= 0 || arguments == nullptr || command_line == nullptr) {
    return false;
  }
  std::wstring joined;
  for (int index = 0; index < argument_count; ++index) {
    if (index != 0) {
      joined.push_back(L' ');
    }
    joined.append(QuoteCommandLineArgument(arguments[index]));
    if (joined.size() >= 32767) {
      SetLastError(ERROR_FILENAME_EXCED_RANGE);
      return false;
    }
  }
  command_line->assign(joined.begin(), joined.end());
  command_line->push_back(L'\0');
  return true;
}

UniqueHandle DuplicateStandardHandle(DWORD standard_handle, DWORD null_access) {
  HANDLE source = GetStdHandle(standard_handle);
  DWORD flags = 0;
  if (source != nullptr && source != INVALID_HANDLE_VALUE &&
      GetHandleInformation(source, &flags)) {
    HANDLE duplicate = nullptr;
    if (DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(),
                        &duplicate, 0, TRUE, DUPLICATE_SAME_ACCESS)) {
      return UniqueHandle(duplicate);
    }
  }

  SECURITY_ATTRIBUTES attributes{};
  attributes.nLength = sizeof(attributes);
  attributes.bInheritHandle = TRUE;
  return UniqueHandle(CreateFileW(L"NUL", null_access,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  &attributes, OPEN_EXISTING,
                                  FILE_ATTRIBUTE_NORMAL, nullptr));
}

bool CaptureActiveJobProcesses(HANDLE job,
                               std::vector<UniqueHandle> *processes,
                               DWORD *capture_error) {
  constexpr std::size_t kMaximumProcessCount = 4096;
  constexpr std::size_t kListHeaderBytes =
      offsetof(JOBOBJECT_BASIC_PROCESS_ID_LIST, ProcessIdList);
  std::size_t capacity = 16;
  std::vector<std::uint8_t> storage;
  JOBOBJECT_BASIC_PROCESS_ID_LIST *process_list = nullptr;
  for (;;) {
    storage.resize(kListHeaderBytes + capacity * sizeof(ULONG_PTR));
    process_list = reinterpret_cast<JOBOBJECT_BASIC_PROCESS_ID_LIST *>(
        storage.data());
    if (!QueryInformationJobObject(
            job, JobObjectBasicProcessIdList, process_list,
            static_cast<DWORD>(storage.size()), nullptr)) {
      if (capture_error != nullptr) {
        *capture_error = GetLastError();
      }
      return false;
    }
    if (process_list->NumberOfAssignedProcesses <=
        process_list->NumberOfProcessIdsInList) {
      break;
    }
    capacity = process_list->NumberOfAssignedProcesses;
    if (capacity > kMaximumProcessCount) {
      if (capture_error != nullptr) {
        *capture_error = ERROR_NOT_ENOUGH_MEMORY;
      }
      return false;
    }
  }

  processes->clear();
  processes->reserve(process_list->NumberOfProcessIdsInList);
  for (DWORD index = 0; index < process_list->NumberOfProcessIdsInList;
       ++index) {
    const ULONG_PTR raw_process_id = process_list->ProcessIdList[index];
    if (raw_process_id == 0 ||
        raw_process_id > std::numeric_limits<DWORD>::max()) {
      if (capture_error != nullptr) {
        *capture_error = ERROR_INVALID_DATA;
      }
      return false;
    }
    UniqueHandle process(OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE,
        static_cast<DWORD>(raw_process_id)));
    if (!process) {
      const DWORD error = GetLastError();
      if (error == ERROR_INVALID_PARAMETER) {
        continue;
      }
      if (capture_error != nullptr) {
        *capture_error = error;
      }
      return false;
    }
    BOOL in_job = FALSE;
    if (!IsProcessInJob(process.Get(), job, &in_job)) {
      if (capture_error != nullptr) {
        *capture_error = GetLastError();
      }
      return false;
    }
    if (in_job) {
      processes->push_back(std::move(process));
    }
  }
  return true;
}

bool TerminateAndDrainJob(HANDLE job, DWORD process_exit_code,
                          DWORD *cleanup_error) {
  std::vector<UniqueHandle> active_processes;
  DWORD capture_error = ERROR_SUCCESS;
  const bool captured =
      CaptureActiveJobProcesses(job, &active_processes, &capture_error);
  DWORD termination_error = ERROR_SUCCESS;
  if (!TerminateJobObject(job, process_exit_code)) {
    termination_error = GetLastError();
  }

  const ULONGLONG deadline =
      GetTickCount64() + kJobDrainTimeoutMilliseconds;
  for (const auto &process : active_processes) {
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline ||
        WaitForSingleObject(process.Get(), static_cast<DWORD>(deadline - now)) !=
            WAIT_OBJECT_0) {
      if (cleanup_error != nullptr) {
        *cleanup_error = termination_error == ERROR_SUCCESS
                             ? ERROR_TIMEOUT
                             : termination_error;
      }
      return false;
    }
  }
  for (;;) {
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
    if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                                   &accounting, sizeof(accounting), nullptr)) {
      if (cleanup_error != nullptr) {
        *cleanup_error = GetLastError();
      }
      return false;
    }
    if (accounting.ActiveProcesses == 0) {
      if (captured) {
        return true;
      }
      if (cleanup_error != nullptr) {
        *cleanup_error = capture_error;
      }
      return false;
    }
    if (GetTickCount64() >= deadline) {
      if (cleanup_error != nullptr) {
        *cleanup_error = termination_error == ERROR_SUCCESS
                             ? ERROR_TIMEOUT
                             : termination_error;
      }
      return false;
    }
    Sleep(10);
  }
}

DWORD CleanupFailure(HANDLE job, DWORD process_exit_code) {
  DWORD cleanup_error = ERROR_SUCCESS;
  if (TerminateAndDrainJob(job, process_exit_code, &cleanup_error)) {
    return ERROR_SUCCESS;
  }
  ReportFailure(L"the contained process tree could not be proven stopped",
                cleanup_error);
  return kJobCleanupFailed;
}

DWORD RunHost(int argc, wchar_t **argv) {
  if (argc < 5 || wcscmp(argv[1], L"--owner-pid") != 0 ||
      wcscmp(argv[3], L"--") != 0) {
    ReportFailure(L"expected --owner-pid <PID> -- <absolute target> [args]",
                  ERROR_BAD_ARGUMENTS);
    return ERROR_BAD_ARGUMENTS;
  }

  DWORD owner_process_id = 0;
  if (!ParseProcessId(argv[2], &owner_process_id) ||
      owner_process_id == GetCurrentProcessId()) {
    ReportFailure(L"the owner process ID is invalid", ERROR_INVALID_PARAMETER);
    return ERROR_INVALID_PARAMETER;
  }

  const std::wstring target(argv[4]);
  if (!IsAbsolutePath(target)) {
    ReportFailure(L"the target executable path is not absolute",
                  ERROR_INVALID_PARAMETER);
    return ERROR_INVALID_PARAMETER;
  }

  UniqueHandle owner(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                                 FALSE, owner_process_id));
  if (!owner) {
    const DWORD error = GetLastError();
    ReportFailure(L"the owner process could not be opened", error);
    return error;
  }
  const DWORD initial_owner_state = WaitForSingleObject(owner.Get(), 0);
  if (initial_owner_state == WAIT_OBJECT_0) {
    ReportFailure(L"the owner process is no longer running", kOwnerExited);
    return kOwnerExited;
  }
  if (initial_owner_state == WAIT_FAILED) {
    const DWORD error = GetLastError();
    ReportFailure(L"the owner process state could not be verified", error);
    return error;
  }

  UniqueHandle job(CreateJobObjectW(nullptr, nullptr));
  if (!job) {
    const DWORD error = GetLastError();
    ReportFailure(L"the containment job could not be created", error);
    return error;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job.Get(), JobObjectExtendedLimitInformation,
                               &limits, sizeof(limits))) {
    const DWORD error = GetLastError();
    ReportFailure(L"the containment job could not be configured", error);
    return error;
  }

  UniqueHandle standard_input =
      DuplicateStandardHandle(STD_INPUT_HANDLE, GENERIC_READ);
  UniqueHandle standard_output =
      DuplicateStandardHandle(STD_OUTPUT_HANDLE, GENERIC_WRITE);
  UniqueHandle standard_error =
      DuplicateStandardHandle(STD_ERROR_HANDLE, GENERIC_WRITE);
  if (!standard_input || !standard_output || !standard_error) {
    const DWORD error = GetLastError();
    ReportFailure(L"the target standard handles could not be prepared", error);
    return error;
  }

  AttributeList attributes;
  if (!attributes.Initialize(2)) {
    const DWORD error = GetLastError();
    ReportFailure(L"the target startup policy could not be initialized", error);
    return error;
  }
  HANDLE job_list[] = {job.Get()};
  if (!attributes.Set(PROC_THREAD_ATTRIBUTE_JOB_LIST, job_list,
                      sizeof(job_list))) {
    const DWORD error = GetLastError();
    ReportFailure(L"the containment job could not be attached atomically",
                  error);
    return error;
  }
  HANDLE inherited_handles[] = {standard_input.Get(), standard_output.Get(),
                                standard_error.Get()};
  if (!attributes.Set(PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited_handles,
                      sizeof(inherited_handles))) {
    const DWORD error = GetLastError();
    ReportFailure(L"the target handle policy could not be restricted", error);
    return error;
  }

  std::vector<wchar_t> command_line;
  if (!BuildCommandLine(argc - 4, argv + 4, &command_line)) {
    const DWORD error = GetLastError();
    ReportFailure(L"the target command line is too long", error);
    return error;
  }

  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = standard_input.Get();
  startup.StartupInfo.hStdOutput = standard_output.Get();
  startup.StartupInfo.hStdError = standard_error.Get();
  startup.lpAttributeList = attributes.Get();

  PROCESS_INFORMATION process_information{};
  constexpr DWORD creation_flags = CREATE_SUSPENDED | CREATE_NO_WINDOW |
                                   EXTENDED_STARTUPINFO_PRESENT |
                                   CREATE_UNICODE_ENVIRONMENT;
  if (!CreateProcessW(target.c_str(), command_line.data(), nullptr, nullptr, TRUE,
                      creation_flags, nullptr, nullptr,
                      &startup.StartupInfo, &process_information)) {
    const DWORD error = GetLastError();
    ReportFailure(L"the target process could not be created", error);
    return error;
  }
  UniqueHandle target_process(process_information.hProcess);
  UniqueHandle target_thread(process_information.hThread);

  const DWORD owner_state = WaitForSingleObject(owner.Get(), 0);
  if (owner_state == WAIT_OBJECT_0 || owner_state == WAIT_FAILED) {
    const DWORD error = owner_state == WAIT_OBJECT_0 ? kOwnerExited
                                                     : GetLastError();
    const DWORD cleanup_result = CleanupFailure(job.Get(), error);
    if (cleanup_result != ERROR_SUCCESS) {
      return cleanup_result;
    }
    ReportFailure(owner_state == WAIT_OBJECT_0
                      ? L"the owner exited before the target could start"
                      : L"the owner state could not be verified",
                  error);
    return error;
  }

  if (ResumeThread(target_thread.Get()) == static_cast<DWORD>(-1)) {
    const DWORD error = GetLastError();
    const DWORD cleanup_result = CleanupFailure(job.Get(), error);
    if (cleanup_result != ERROR_SUCCESS) {
      return cleanup_result;
    }
    ReportFailure(L"the contained target could not be resumed", error);
    return error;
  }
  target_thread.Reset();

  HANDLE watched[] = {target_process.Get(), owner.Get()};
  const DWORD wait_result = WaitForMultipleObjects(2, watched, FALSE, INFINITE);
  if (wait_result == WAIT_OBJECT_0) {
    DWORD exit_code = ERROR_PROCESS_ABORTED;
    if (!GetExitCodeProcess(target_process.Get(), &exit_code)) {
      const DWORD error = GetLastError();
      const DWORD cleanup_result = CleanupFailure(job.Get(), error);
      if (cleanup_result != ERROR_SUCCESS) {
        return cleanup_result;
      }
      ReportFailure(L"the target exit status could not be read", error);
      return error;
    }
    const DWORD cleanup_result = CleanupFailure(job.Get(), kOwnerExited);
    if (cleanup_result != ERROR_SUCCESS) {
      return cleanup_result;
    }
    return exit_code;
  }
  if (wait_result == WAIT_OBJECT_0 + 1) {
    const DWORD cleanup_result = CleanupFailure(job.Get(), kOwnerExited);
    if (cleanup_result != ERROR_SUCCESS) {
      return cleanup_result;
    }
    return kOwnerExited;
  }

  const DWORD error =
      wait_result == WAIT_FAILED ? GetLastError() : ERROR_PROCESS_ABORTED;
  const DWORD cleanup_result = CleanupFailure(job.Get(), error);
  if (cleanup_result != ERROR_SUCCESS) {
    return cleanup_result;
  }
  ReportFailure(L"the owner/target wait failed", error);
  return error;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return static_cast<int>(GetLastError());
  }
  const DWORD result = RunHost(argc, argv);
  LocalFree(argv);
  return static_cast<int>(result);
}
