import SwiftUI
import UniformTypeIdentifiers

// MARK: - 拖放 / 选择素材区

struct SourceDropView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropArea
            if !appModel.inputs.isEmpty {
                inputList
            }
        }
    }

    private var dropArea: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(appModel.isDropTargeted ? Color.accentColor : Color.secondary)
            Text("拖入图片、视频或文件夹")
                .font(.subheadline.weight(.medium))
            Text("支持 PNG / JPG / WebP 与 MP4 / MOV / MKV 等，可多选")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                appModel.pickFiles()
            } label: {
                Label("选择素材…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appModel.isDropTargeted
                      ? Color.accentColor.opacity(0.12)
                      : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(appModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $appModel.isDropTargeted) { providers in
            appModel.handleDrop(providers)
            return true
        }
    }

    private var inputList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已添加 \(appModel.inputs.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") { appModel.clearInputs() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(appModel.inputs) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isDirectory
                                  ? "folder"
                                  : (FileTools.isVideo(item.url) ? "film" : "photo"))
                                .foregroundStyle(.secondary)
                            Text(item.url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if item.fileSize > 0 {
                                Text(FileTools.formatBytes(item.fileSize))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                appModel.removeInput(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}

// MARK: - 任务选择

struct TaskPickerView: View {
    @EnvironmentObject var appModel: AppModel

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TaskKind.allCases) { kind in
                Button {
                    appModel.task = kind
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.callout.weight(.semibold))
                            Text(kind.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(appModel.task == kind
                                  ? Color.accentColor.opacity(0.15)
                                  : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(appModel.task == kind
                                          ? Color.accentColor
                                          : Color.primary.opacity(0.08),
                                          lineWidth: appModel.task == kind ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
