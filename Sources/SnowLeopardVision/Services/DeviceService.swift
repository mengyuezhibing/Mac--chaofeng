import Foundation

// MARK: - 设备信息（Apple Silicon / GPU / 内存）

struct GPUInfo: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var vram: String?
    var metalSupport: String?
}

struct MachineInfo {
    var chipName: String = "未知"
    var memoryDescription: String = "未知"
    var macOSVersion: String = "未知"
    var runningUnderRosetta: Bool = false
    var gpus: [GPUInfo] = []

    var summary: String {
        var lines: [String] = []
        lines.append("芯片：\(chipName)")
        lines.append("内存：\(memoryDescription)")
        lines.append("系统：macOS \(macOSVersion)")
        if runningUnderRosetta {
            lines.append("注意：当前运行在 Rosetta 转译模式下，建议使用原生 arm64 构建")
        }
        if gpus.isEmpty {
            lines.append("GPU：未能识别")
        } else {
            for gpu in gpus {
                var text = "GPU：\(gpu.name)"
                if let vram = gpu.vram, !vram.isEmpty { text += "（\(vram)）" }
                if let metal = gpu.metalSupport, !metal.isEmpty { text += " · \(metal)" }
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum DeviceService {

    /// 优先本地快速探测；GPU 详情通过 system_profiler 获取
    static func probeMachineInfo() async -> MachineInfo {
        var info = MachineInfo()

        let chip = (try? await ProcessRunner.capture(executable: "/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"]))?
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let chip, !chip.isEmpty { info.chipName = chip }

        if let memory = try? await ProcessRunner.capture(executable: "/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"]) {
            let bytes = Int64(memory.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if bytes > 0 { info.memoryDescription = FileTools.formatBytes(bytes) }
        }

        if let version = try? await ProcessRunner.capture(executable: "/usr/bin/sw_vers", arguments: ["-productVersion"]) {
            let value = version.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { info.macOSVersion = value }
        }

        let rosetta = (try? await ProcessRunner.capture(executable: "/usr/sbin/sysctl", arguments: ["-n", "sysctl.proc_translated"]))?
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        info.runningUnderRosetta = rosetta == "1"

        info.gpus = await probeGPUs()
        return info
    }

    private static func probeGPUs() async -> [GPUInfo] {
        guard let result = try? await ProcessRunner.capture(
            executable: "/usr/sbin/system_profiler",
            arguments: ["-json", "SPDisplaysDataType"]
        ), result.status == 0,
        let data = result.output.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var gpus: [GPUInfo] = []
        guard let displays = object["SPDisplaysDataType"] as? [[String: Any]] else { return [] }

        func extractGPU(_ dictionary: [String: Any]) -> GPUInfo? {
            guard let name = (dictionary["_name"] as? String)
                ?? (dictionary["sppci_model"] as? String) else { return nil }
            let vram = (dictionary["spdisplays_vram_shared"] as? String)
                ?? (dictionary["spdisplays_vram"] as? String)
            let metal = (dictionary["spdisplays_mtlgpufamilysupport"] as? String)
                ?? (dictionary["_spdisplays_metal"] as? String)
            return GPUInfo(name: name, vram: vram, metalSupport: metal)
        }

        for display in displays {
            if let gpu = extractGPU(display) { gpus.append(gpu) }
            if let children = display["spdisplays_ndrvs"] as? [[String: Any]] {
                for child in children {
                    if let gpu = extractGPU(child) { gpus.append(gpu) }
                }
            }
        }
        return gpus
    }
}
