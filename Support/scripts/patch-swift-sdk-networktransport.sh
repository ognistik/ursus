#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
TARGET_FILE="$ROOT_DIR/.build/checkouts/swift-sdk/Sources/MCP/Base/Transports/NetworkTransport.swift"

if [ ! -f "$TARGET_FILE" ]; then
  exit 0
fi

if grep -q "_MCPContinuationResumeFlag" "$TARGET_FILE"; then
  exit 0
fi

perl -0pi -e '
  s/import Logging\n/import Logging\n\nprivate final class _MCPContinuationResumeFlag: \@unchecked Sendable {\n    private let lock = NSLock()\n    private var resumed = false\n\n    func begin() -> Bool {\n        lock.lock()\n        defer { lock.unlock() }\n        if resumed {\n            return false\n        }\n        resumed = true\n        return true\n    }\n}\n\n/;
  s/var sendContinuationResumed = false/let sendContinuationResumed = _MCPContinuationResumeFlag()/g;
  s/if !sendContinuationResumed \{\n\s*sendContinuationResumed = true/if sendContinuationResumed.begin() {/g;
  s/var receiveContinuationResumed = false/let receiveContinuationResumed = _MCPContinuationResumeFlag()/g;
  s/if !receiveContinuationResumed \{\n\s*receiveContinuationResumed = true/if receiveContinuationResumed.begin() {/g;
' "$TARGET_FILE"

echo "Patched swift-sdk NetworkTransport.swift for current Swift toolchain"
