import SwiftUI

// MARK: - 参数设置面板

struct SettingsPanelView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appModel.task.needsSuperResolution {
                superResolutionSection
                Divider()
            }
            if appModel.task.needsInterpolation {
                interpolationSection
                Divider()
            }
            if !appModel.task.isImageTask {
                encoderSection
                Divider()
            }
            performanceSection
            Divider()
            outputSection
        }
    }

    // MARK: 超分

    private var superResolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(label: "超分算法") {
                Picker("", selection: $appModel.backend) {
                    ForEach(SRBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .labelsHidden()
            }
            SettingRow(label: "模型") {
                HStack {
                    TextField("模型名（留空使用工具默认）", text: $appModel.srModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    if appModel.backend == .realCUGAN {
                        Picker("", selection: $appModel.cuganNoise) {
                            Text("降噪 -1").tag(-1)
                            Text("无降噪 0").tag(0)
                            Text("降噪 1").tag(1)
                            Text("降噪 2").tag(2)
                            Text("降噪 3").tag(3)
                        }
                        .frame(width: 120)
                        .labelsHidden()
                    }
                }
            }
            SettingRow(label: "放大倍数") {
                Picker("", selection: $appModel.scale) {
                    ForEach(appModel.backend.supportedScales, id: \.self) { scale in
                        Text("\(scale)x").tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }
            DisclosureGroup("高级参数（追加给超分命令行）") {
                TextField("例如：-x（TTA）或 -m /path/to/models", text: $appModel.extraSRArguments)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.caption)
            Text(appModel.backend.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 补帧

    private var interpolationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(label: "补帧模型") {
                TextField("例如 rife-v4.6（留空使用工具默认）", text: $appModel.interpModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            SettingRow(label: "补帧倍数") {
                Picker("", selection: $appModel.fpsMultiplier) {
                    Text("2x（推荐）").tag(2)
                    Text("4x").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
                Text("4x 会将补帧执行两遍，耗时翻倍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("高级参数（追加给补帧命令行）") {
                TextField("例如：-m /path/to/models 或 -u（UHD）", text: $appModel.extraInterpArguments)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.caption)
        }
    }

    // MARK: 编码

    private var encoderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(label: "视频编码") {
                Picker("", selection: $appModel.encoder) {
                    ForEach(VideoEncoder.allCases) { encoder in
                        Text(encoder.displayName).tag(encoder)
                    }
                }
                .frame(maxWidth: 380)
                .labelsHidden()
            }
            if appModel.encoder.usesBitrate {
                SettingRow(label: "视频码率") {
                    Slider(value: $appModel.bitrateMbps, in: 2...120, step: 1) {
                        Text("码率")
                    }
                    .frame(maxWidth: 280)
                    Text("\(Int(appModel.bitrateMbps)) Mbps")
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            } else if appModel.encoder.usesCRF {
                SettingRow(label: "质量 (CRF)") {
                    Slider(value: Binding(get: { Double(appModel.crf) },
                                          set: { appModel.crf = Int($0) }),
                           in: 14...28, step: 1)
                        .frame(maxWidth: 280)
                    Text("CRF \(appModel.crf)")
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
            SettingRow(label: "音频") {
                Toggle("保留原视频音轨", isOn: $appModel.keepAudio)
            }
            Toggle("10-bit 输出（仅 HEVC，适合 HDR/高色深素材）", isOn: $appModel.tenBitOutput)
                .disabled(!appModel.encoder.supportsTenBit)
                .font(.callout)
        }
    }

    // MARK: 性能

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(label: "性能档位") {
                Picker("", selection: $appModel.performance) {
                    ForEach(PerformanceTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .labelsHidden()
            }
            SettingRow(label: "GPU 设备") {
                Stepper(value: $appModel.gpuIndex, in: 0...7) {
                    Text("#\(appModel.gpuIndex)")
                }
                .frame(width: 140)
                Text("Apple 芯片内置显卡通常为 #0；如检测到外接显卡可尝试其他编号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 输出

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(label: "输出目录") {
                HStack {
                    Text(appModel.outputDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("更改…") { appModel.pickOutputDirectory() }
                }
            }
            SettingRow(label: "输出文件名") {
                TextField("留空则按 素材名_参数 自动生成", text: $appModel.outputName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            if appModel.task.isImageTask {
                SettingRow(label: "输出格式") {
                    Picker("", selection: $appModel.imageOutputFormat) {
                        ForEach(ImageOutputFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .labelsHidden()
                }
            } else {
                SettingRow(label: "中间帧格式") {
                    Picker("", selection: $appModel.intermediateFormat) {
                        ForEach(IntermediateFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .frame(width: 260)
                    .labelsHidden()
                }
                Toggle("保留中间帧目录（用于排查问题）", isOn: $appModel.keepIntermediateFiles)
                    .font(.callout)
            }
        }
    }
}
