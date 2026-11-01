#include "InputBridge.h"
#include <iostream>
#include <system_error>
using namespace InputBridge;

int main() try {
    std::cout
        << "Print and block mouse input. Keyboard and controller input keep working.\n"
           "Run one example at a time as administrator. Close this window or press Ctrl+C to stop.\n"
        << std::flush;
    // Check installation and initialize supported devices before capturing.
    Status();
    const auto init = Initialize();
    if (init.reboot_required) {
        std::cerr << "Restart Windows, then run this example again.\n";
        return ERROR_SUCCESS_REBOOT_REQUIRED;
    }
    if (!init.ready) {
        std::cerr << "Initialization failed: " << init.error_detail
                  << ". Windows error: " << init.error
                  << ". Restart required: " << init.reboot_required << "\n";
        return 1;
    }
    DWORD consoleMode = 0; // Console only: prevent text selection from blocking console writes.
    if (GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &consoleMode)) {
        SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE),
                       (consoleMode | ENABLE_EXTENDED_FLAGS) & ~ENABLE_QUICK_EDIT_MODE);
    }
    for (;;) {
        // Receive: wait for input without polling.
        auto inputs = Read(INFINITE);
        for (auto& input : inputs) {
            if (input.Get<MouseEvent>()) {
                input.blocked = true;
            }
        }
        // Forward: send all unblocked inputs, including other device types.
        const auto sent = Write(inputs);
        if (!sent) {
            throw std::system_error(sent.error, std::system_category(), "Write");
        }
        for (auto& input : inputs) {
            if (auto* mouse = input.Get<MouseEvent>()) {
                input.blocked = true; // Other input families are forwarded below.
                std::cout << "Mouse " << mouse->device << ": x=" << mouse->state.x
                          << " y=" << mouse->state.y << " buttons=" << mouse->state.button_flags
                          << " wheel=" << mouse->state.button_data << '\n';
            }
        }
    }
} catch (const std::system_error& error) {
    std::cerr
        << "Driver error: " << error.what() << ". Windows error: " << error.code().value()
        << ". Install this edition with InputBridgeSetup.exe, restart if requested, and run as administrator.\n";
    return 1;
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
