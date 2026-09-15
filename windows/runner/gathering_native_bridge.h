#ifndef RUNNER_GATHERING_NATIVE_BRIDGE_H_
#define RUNNER_GATHERING_NATIVE_BRIDGE_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateGatheringNativeBridge(
    flutter::BinaryMessenger* messenger, HWND window);

#endif
