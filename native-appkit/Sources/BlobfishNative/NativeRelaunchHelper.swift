import Foundation

enum NativeRelaunchHelper {
    // Wait for the old process and its single-instance lock to disappear.
    // Paths are arguments, never interpolated shell source.
    static func arguments(parentPID: Int32, command: [String], attempts: Int = 200) -> [String] {
        precondition(parentPID > 0 && attempts > 0 && !command.isEmpty)
        let script = """
        trap '' HUP
        parent_pid="$1"
        remaining="$2"
        shift 2
        while /bin/kill -0 "$parent_pid" 2>/dev/null; do
            if [ "$remaining" -le 0 ]; then exit 75; fi
            remaining=$((remaining - 1))
            /bin/sleep 0.1
        done
        exec "$@"
        """
        return ["-c", script, "blobfish-relaunch", String(parentPID), String(attempts)] + command
    }
}
