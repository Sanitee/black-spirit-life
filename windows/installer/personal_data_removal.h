#pragma once

#include <cstdint>
#include <functional>
#include <string>

namespace bsl::installer {

enum class PersonalDataRemovalStatus {
  none,
  prepared,
  application_removed,
  cleanup_pending,
  complete,
  invalid,
};

struct PersonalDataRemovalTarget {
  bool present = false;
  bool quarantined = false;
  bool recycled = false;
  std::wstring path;
  std::wstring quarantine_path;
  std::uint32_t volume_serial = 0;
  std::uint64_t file_id = 0;
  std::uint32_t parent_volume_serial = 0;
  std::uint64_t parent_file_id = 0;
};

struct PersonalDataRemovalPlan {
  PersonalDataRemovalStatus status = PersonalDataRemovalStatus::none;
  std::wstring transaction_id;
  std::wstring journal_path;
  std::wstring journal_mirror_path;
  std::uint32_t journal_directory_volume_serial = 0;
  std::uint64_t journal_directory_file_id = 0;
  std::wstring reset_marker_path;
  std::wstring install_root;
  std::wstring registered_install_root;
  std::wstring installed_version;
  std::uint32_t install_root_volume_serial = 0;
  std::uint64_t install_root_file_id = 0;
  bool custom_profile = false;
  PersonalDataRemovalTarget active_profile;
  PersonalDataRemovalTarget local_data;
};

struct PersonalDataRemovalResult {
  bool success = false;
  bool application_removed = false;
  bool removed = false;
  bool retained_quarantine = false;
  bool retry_available = false;
  PersonalDataRemovalStatus status = PersonalDataRemovalStatus::invalid;
  std::wstring message;
  std::wstring journal_path;
};

// Preflights the exact active profile and app-local cache/control root,
// captures their physical identities, and commits a durable opt-in journal.
// It never removes or renames user data.
PersonalDataRemovalResult
PreparePersonalDataRemoval(const std::wstring &install_root,
                           PersonalDataRemovalPlan *plan);

// Detects a durable consent/cleanup journal even after Velopack has removed the
// application. Detection never removes planner data.
PersonalDataRemovalResult
DetectPendingPersonalDataRemoval(PersonalDataRemovalPlan *plan);

// Returns true only when a prepared consent record still belongs to the exact
// installed application object and registration captured during preflight.
// A replacement installation at the same lexical path never matches.
[[nodiscard]] bool PreparedPersonalDataRemovalMatchesInstallation(
    const PersonalDataRemovalPlan &plan, const std::wstring &install_root,
    const std::wstring &registered_install_root,
    const std::wstring &installed_version,
    std::uint32_t install_root_volume_serial,
    std::uint64_t install_root_file_id);

// Commits the point at which the caller has independently proved that the
// application uninstall completed. Cleanup is refused before this transition.
PersonalDataRemovalResult MarkPersonalDataApplicationRemoved(
    const PersonalDataRemovalPlan &plan);

// Cancels durable consent only while the captured application and every
// original data target still match the prepared snapshot. It refuses after
// application removal or any quarantine transition.
PersonalDataRemovalResult
CancelPreparedPersonalDataRemoval(const PersonalDataRemovalPlan &plan);

// Quarantines the exact captured directory objects, sends those quarantines to
// the Windows Recycle Bin, writes the one-time legacy-import suppression
// marker, and clears the consent journal. There is no permanent-delete fallback.
PersonalDataRemovalResult
FinalizePersonalDataRemoval(const PersonalDataRemovalPlan &plan);

// Resumes a previously committed cleanup transaction. A prepared transaction
// advances only after the captured application-removal proof succeeds.
PersonalDataRemovalResult RetryPendingPersonalDataRemoval();

// Isolated dependency injection for native tests. Production code should use
// the overloads above, which resolve Windows Known Folders and IFileOperation.
using PersonalDataRecycleCallback =
    std::function<bool(const std::wstring &path, std::wstring *error)>;

struct PersonalDataRemovalTestEnvironment {
  std::wstring roaming_app_data;
  std::wstring local_app_data;
  std::wstring journal_directory;
};

PersonalDataRemovalResult PreparePersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &environment,
    const std::wstring &install_root,
    PersonalDataRemovalPlan *plan);
PersonalDataRemovalResult DetectPendingPersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &environment,
    PersonalDataRemovalPlan *plan);
PersonalDataRemovalResult FinalizePersonalDataRemovalForTesting(
    const PersonalDataRemovalPlan &plan,
    const PersonalDataRecycleCallback &recycle);
PersonalDataRemovalResult RetryPendingPersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &environment,
    const PersonalDataRecycleCallback &recycle);
PersonalDataRemovalResult MarkPersonalDataApplicationRemovedForTesting(
    const PersonalDataRemovalPlan &plan);
PersonalDataRemovalResult CancelPreparedPersonalDataRemovalForTesting(
    const PersonalDataRemovalPlan &plan);

} // namespace bsl::installer
