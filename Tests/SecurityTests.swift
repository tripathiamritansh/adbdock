import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct SecurityTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw NSError(domain: label, code: 1) }
        checks += 1
    }

    static func main() throws {
        // Child modes exercise actual pipes and termination, without adb or a phone.
        if CommandLine.arguments.contains("--flood") {
            FileHandle.standardOutput.write(Data(repeating: 65, count: 2 << 20))
            FileHandle.standardError.write(Data(repeating: 66, count: 2 << 20))
            return
        }
        if CommandLine.arguments.contains("--ignore-term") {
            signal(SIGTERM, SIG_IGN)
            while true { Thread.sleep(forTimeInterval: 0.1) }
        }
        if CommandLine.arguments.contains("--stdin-eof") {
            print(FileHandle.standardInput.readDataToEndOfFile().count)
            return
        }
        if CommandLine.arguments.contains("--exit") { return }

        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("adbdock-security-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        let fake = temp.appendingPathComponent("adb")
        let argsFile = temp.appendingPathComponent("arguments")
        try """
        #!/bin/sh
        case "$1" in
          version) printf 'Android Debug Bridge version test\\n' ;;
          pair)
            printf '%s\\n' "$@" > "$ADBDOCK_TEST_ARGS"
            IFS= read -r code || exit 2
            [ "$#" -eq 2 ] && [ "$code" = 123456 ] || exit 3
            printf 'Successfully paired; echoed input: %s\\n' "$code"
            [ "$2" != fail ] || exit 1
            ;;
          connect) printf 'connected to test\\n'; exit 1 ;;
          *) exit 4 ;;
        esac
        """.write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        setenv("ADB", fake.path, 1)
        setenv("ADBDOCK_TEST_ARGS", argsFile.path, 1)

        let adb = Adb.shared
        let result = adb.pair(address: "192.0.2.1:5555", code: "123456")
        try expect(result.ok, "pairing code must arrive on stdin")
        let arguments = try String(contentsOf: argsFile, encoding: .utf8)
        try expect(arguments == "pair\n192.0.2.1:5555\n", "pairing code must not appear in argv")
        try expect(!result.message.contains("123456") && result.message.contains("[redacted]"),
                   "echoed pairing codes must be redacted")
        try expect(!adb.pair(address: "fail", code: "123456").ok, "failed pair exit must override success text")
        try expect(!adb.connect("test").ok, "failed connect exit must override success text")

        try fm.removeItem(at: argsFile)
        for code in ["", "12345", "1234567", "12345\n", "12a456", "１２３４５６"] {
            try expect(!adb.pair(address: "192.0.2.1:5555", code: code).ok, "invalid code must be rejected")
        }
        try expect(!fm.fileExists(atPath: argsFile.path), "invalid codes must not launch adb")

        let pairing = MdnsService(instance: "adb-test-old", type: "_adb-tls-pairing._tcp",
                                  address: "[2001:db8::1]:5555")
        let spoofed = MdnsService(instance: "adb-test-new", type: "_adb-tls-connect._tcp",
                                  address: "[2001:db8::2]:5556")
        let legitimate = MdnsService(instance: "adb-test-new", type: "_adb-tls-connect._tcp",
                                     address: "[2001:db8::1]:5557")
        try expect(pairing.ip == "2001:db8::1", "IPv6 hosts must not collapse to the first colon")
        try expect(MdnsService.connection(afterPairing: pairing, among: [spoofed]) == nil,
                   "a copied serial on another host must not be selected")
        try expect(MdnsService.connection(afterPairing: pairing, among: [spoofed, legitimate])?.address == legitimate.address,
                   "connection must remain on the confirmed host")
        try expect(MdnsService.connection(afterPairing: pairing, among: [pairing]) == nil,
                   "pairing advertisements are not connection services")

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let flooded = Adb.exec(executable, ["--flood"], timeout: 5)
        try expect(flooded.code == 0 && flooded.out.utf8.count == 1 << 20 && flooded.err.utf8.count == 1 << 20,
                   "stdout and stderr must drain concurrently with bounded capture")
        let start = Date()
        let stuck = Adb.exec(executable, ["--ignore-term"], timeout: 0.2)
        try expect(stuck.code != 0 && Date().timeIntervalSince(start) < 5,
                   "a child ignoring SIGTERM must be killed")
        try expect(Adb.exec(executable, ["--stdin-eof"], timeout: 2).out == "0\n",
                   "commands without input must receive EOF")
        try expect(Adb.exec(executable, ["--exit"], timeout: 2, input: "123456\n").code == 0,
                   "an early child exit must not cause SIGPIPE")
        try expect(Adb.exec(executable, ["--exit"], timeout: 2, input: String(repeating: "x", count: 513)).code == -1,
                   "oversized pipe input must be rejected before launch")
        print("Passed \(checks) security checks")
    }
}
