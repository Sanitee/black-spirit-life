#ifndef RUNNER_ACTIVE_NODE_SCAN_PROTOCOL_H_
#define RUNNER_ACTIVE_NODE_SCAN_PROTOCOL_H_

#include <filesystem>
#include <optional>
#include <string>

#include "active_node_video_scanner.h"

namespace active_node_scan_protocol {

bool WriteResultAtomic(
    const std::filesystem::path& path,
    const active_node_video_scanner::ScanResult& result,
    std::string* error = nullptr);

std::optional<active_node_video_scanner::ScanResult> ReadResult(
    const std::filesystem::path& path,
    std::string* error = nullptr);

bool WriteProgressAtomic(
    const std::filesystem::path& path,
    const active_node_video_scanner::ScanProgress& progress,
    std::string* error = nullptr);

std::optional<active_node_video_scanner::ScanProgress> ReadProgress(
    const std::filesystem::path& path);

}  // namespace active_node_scan_protocol

#endif  // RUNNER_ACTIVE_NODE_SCAN_PROTOCOL_H_
