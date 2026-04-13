import SwiftUI
import UniformTypeIdentifiers
import Combine
import Foundation
import AVFoundation
import Vision
import AppKit

// MARK: - 1. 全局多语言引擎
enum AppLanguage: String, CaseIterable {
    case en = "English"
    case zhHans = "简体中文"
    case zhHant = "繁體中文"
    case ja = "日本語"
    case fr = "Français"
}

func tr(_ key: String, lang: AppLanguage) -> String {
    let dict: [String: [AppLanguage: String]] = [
        "Editor & Import":      [.en: "Editor",           .zhHans: "编辑与导入",  .zhHant: "編輯與導入",  .ja: "編集",           .fr: "Éditeur"],
        "Process Queue":        [.en: "Queue",             .zhHans: "处理序列",    .zhHant: "處理序列",    .ja: "キュー",         .fr: "File"],
        "Import Videos":        [.en: "Import Videos",    .zhHans: "导入视频",    .zhHant: "導入視頻",    .ja: "動画を読み込む", .fr: "Importer vidéos"],
        "Open Recent":          [.en: "Open Recent",      .zhHans: "打开最近",    .zhHant: "打開最近",    .ja: "最近使った項目", .fr: "Ouvrir récent"],
        "No Recent Files":      [.en: "No Recent Files",  .zhHans: "无最近文件",  .zhHant: "無最近文件",  .ja: "最近のファイルなし", .fr: "Aucun fichier récent"],
        "Process":              [.en: "Process",           .zhHans: "处理",        .zhHant: "處理",        .ja: "処理",           .fr: "Traiter"],
        "Add to Queue":         [.en: "Add to Queue",     .zhHans: "加入序列",    .zhHant: "加入序列",    .ja: "キューに追加",   .fr: "Ajouter à la file"],
        "Basic Info":           [.en: "Basic Info",       .zhHans: "基础信息",    .zhHant: "基礎信息",    .ja: "基本情報",       .fr: "Infos de base"],
        "Title":                [.en: "Title",             .zhHans: "标题",        .zhHant: "標題",        .ja: "タイトル",       .fr: "Titre"],
        "Year":                 [.en: "Year",              .zhHans: "年份",        .zhHant: "年份",        .ja: "公開年",         .fr: "Année"],
        "Director":             [.en: "Director",          .zhHans: "导演",        .zhHant: "導演",        .ja: "監督",           .fr: "Réalisateur"],
        "Genres":               [.en: "Genres",            .zhHans: "类型",        .zhHant: "類型",        .ja: "ジャンル",       .fr: "Genres"],
        "Actors":               [.en: "Actors",            .zhHans: "演员",        .zhHant: "演員",        .ja: "出演者",         .fr: "Acteurs"],
        "Plot":                 [.en: "Plot",              .zhHans: "剧情简介",    .zhHant: "劇情簡介",    .ja: "あらすじ",       .fr: "Synopsis"],
        "Rating":               [.en: "Rating",            .zhHans: "评分",        .zhHant: "評分",        .ja: "評価",           .fr: "Note"],
        "Settings":             [.en: "Settings",          .zhHans: "设置",        .zhHant: "設置",        .ja: "設定",           .fr: "Paramètres"],
        "Appearance & Lang":    [.en: "Appearance & Language", .zhHans: "外观与语言", .zhHant: "外觀與語言", .ja: "外観と表示言語", .fr: "Apparence et langue"],
        "Theme Setting":        [.en: "Theme:",            .zhHans: "主题设定:",   .zhHant: "主題設定:",   .ja: "テーマ設定:",   .fr: "Thème :"],
        "App Language":         [.en: "App Language:",     .zhHans: "应用语言:",   .zhHant: "應用語言:",   .ja: "アプリ言語:",   .fr: "Langue :"],
        "Cache Management":     [.en: "Cache Management", .zhHans: "缓存管理",    .zhHant: "緩存管理",    .ja: "キャッシュ管理", .fr: "Gestion du cache"],
        "Cache Hint":           [.en: "The app records directors, genres and actors for quick autocomplete.",
                                  .zhHans: "系统会自动记录导演、类型、演员等信息，下次输入时可快速补全。",
                                  .zhHant: "系統會自動記錄導演、類型、演員等資訊，下次輸入時可快速補全。",
                                  .ja: "監督・ジャンル・出演者の入力履歴を記録し、次回の入力補完に活用します。",
                                  .fr: "L'app enregistre les réalisateurs, genres et acteurs pour la saisie automatique."],
        "Clear Directors":      [.en: "Clear Directors",  .zhHans: "清除历史导演", .zhHant: "清除歷史導演", .ja: "監督履歴を削除", .fr: "Effacer réalisateurs"],
        "Clear Genres":         [.en: "Clear Genres",     .zhHans: "清除历史类型", .zhHant: "清除歷史類型", .ja: "ジャンル履歴を削除", .fr: "Effacer genres"],
        "Clear Actors":         [.en: "Clear Actors",     .zhHans: "清除历史演员", .zhHant: "清除歷史演員", .ja: "出演者履歴を削除", .fr: "Effacer acteurs"],
        "Clear All":            [.en: "⚠️ Clear All Records", .zhHans: "⚠️ 清除所有记录", .zhHant: "⚠️ 清除所有記錄", .ja: "⚠️ すべての履歴を削除", .fr: "⚠️ Tout effacer"],
        "Import":               [.en: "Import",            .zhHans: "导入",        .zhHant: "導入",        .ja: "読み込む",       .fr: "Importer"],
        "Remove from List":     [.en: "Remove from List", .zhHans: "从列表中移除", .zhHant: "從列表中移除", .ja: "リストから削除", .fr: "Retirer de la liste"],
        "Reveal in Finder":     [.en: "Reveal in Finder", .zhHans: "在 Finder 中显示", .zhHant: "在 Finder 中顯示", .ja: "Finderで表示", .fr: "Afficher dans le Finder"],
        "Sort by Name":         [.en: "Sort by Name",     .zhHans: "按文件名排序", .zhHant: "按檔案名排序", .ja: "名前順に並べ替え", .fr: "Trier par nom"],
        "Sort by Added":        [.en: "Sort by Added",    .zhHans: "按导入顺序排序", .zhHant: "按導入順序排序", .ja: "追加順に並べ替え", .fr: "Trier par ajout"],
        "Drop Videos Here":     [.en: "Drop video files here", .zhHans: "拖入视频文件", .zhHant: "拖入視頻文件", .ja: "動画をドロップ", .fr: "Déposez des vidéos ici"],
        "Selected Count":       [.en: "Selected",          .zhHans: "已选",        .zhHant: "已選",        .ja: "選択中",         .fr: "Sélectionnés"],
        "Rename File":          [.en: "Rename file:",      .zhHans: "重命名文件:",  .zhHant: "重命名檔案:",  .ja: "ファイル名変更:", .fr: "Renommer :"],
        "No Extension":         [.en: "No extension",      .zhHans: "无扩展名",    .zhHant: "無副檔名",    .ja: "拡張子なし",     .fr: "Sans extension"],
        "Select to Edit":       [.en: "Select a video on the left to start editing", .zhHans: "请在左侧选择视频以开始编辑", .zhHant: "請在左側選擇視頻以開始編輯", .ja: "左側で動画を選択して編集開始", .fr: "Sélectionnez une vidéo à gauche pour commencer"],
        "Selected":             [.en: "Selected",          .zhHans: "已选中",      .zhHant: "已選中",      .ja: "選択中",         .fr: "Sélectionné"],
        "Videos":               [.en: "videos",            .zhHans: "个视频",      .zhHant: "個視頻",      .ja: "本の動画",       .fr: "vidéos"],
        "Leave Empty":          [.en: "Leave empty",      .zhHans: "留空",        .zhHant: "留空",        .ja: "空欄のまま",     .fr: "Laisser vide"],
        "Add Genre Hint":       [.en: "Type and press Return to add", .zhHans: "输入影片类型 (回车添加)", .zhHant: "輸入影片類型 (回車添加)", .ja: "入力後Returnで追加", .fr: "Tapez et appuyez sur Entrée"],
        "Quick Add":            [.en: "Quick add:",       .zhHans: "快捷添加:",   .zhHant: "快捷添加:",   .ja: "クイック追加:",  .fr: "Ajout rapide :"],
        "Clear Rating":         [.en: "Clear",            .zhHans: "清除",        .zhHant: "清除",        .ja: "クリア",         .fr: "Effacer"],
        "Actor Name":           [.en: "Name",             .zhHans: "姓名",        .zhHant: "姓名",        .ja: "氏名",           .fr: "Nom"],
        "Actor Role":           [.en: "Role",             .zhHans: "角色",        .zhHant: "角色",        .ja: "役名",           .fr: "Rôle"],
        "Actor Name PH":        [.en: "Actor name",       .zhHans: "演员姓名",    .zhHant: "演員姓名",    .ja: "俳優名",         .fr: "Nom de l'acteur"],
        "Actor Role PH":        [.en: "Character name",   .zhHans: "饰演角色",    .zhHant: "飾演角色",    .ja: "キャラクター名", .fr: "Nom du personnage"],
        "Add Actor":            [.en: "Add Actor",        .zhHans: "添加演员",    .zhHant: "添加演員",    .ja: "出演者を追加",   .fr: "Ajouter un acteur"],
        "Lead Male":            [.en: "Male Lead",        .zhHans: "男主",        .zhHant: "男主",        .ja: "主演（男）",     .fr: "Rôle principal (H)"],
        "Lead Female":          [.en: "Female Lead",      .zhHans: "女主",        .zhHant: "女主",        .ja: "主演（女）",     .fr: "Rôle principal (F)"],
        "Supporting":           [.en: "Supporting",       .zhHans: "配角",        .zhHant: "配角",        .ja: "助演",           .fr: "Second rôle"],
        "Gallery":              [.en: "Poster & Fanart",  .zhHans: "本地图库",    .zhHant: "本地圖庫",    .ja: "ローカル画像",   .fr: "Images locales"],
        "Poster":               [.en: "Poster:",          .zhHans: "封面:",        .zhHant: "封面:",        .ja: "ポスター:",       .fr: "Affiche :"],
        "Fanart":               [.en: "Fanart:",          .zhHans: "背景:",        .zhHant: "背景:",        .ja: "ファンアート:",   .fr: "Fanart :"],
        "Not Selected":         [.en: "Not selected",     .zhHans: "未选择",      .zhHant: "未選擇",      .ja: "未選択",         .fr: "Non sélectionné"],
        "Selected N Images":    [.en: "images selected",  .zhHans: "张已选",      .zhHant: "張已選",      .ja: "枚選択中",       .fr: "images sélectionnées"],
        "Choose":               [.en: "Choose…",          .zhHans: "选择…",       .zhHant: "選擇…",       .ja: "選択…",          .fr: "Choisir…"],
        "Remove":               [.en: "Remove",           .zhHans: "移除",        .zhHant: "移除",        .ja: "削除",           .fr: "Supprimer"],
        "Auto Extract Poster":  [.en: "Auto-detect face from video frame as poster",
                                  .zhHans: "自动从视频画面识别提取人脸作为海报",
                                  .zhHant: "自動從視頻畫面識別提取人臉作為海報",
                                  .ja: "動画フレームから顔を自動検出してポスターに使用",
                                  .fr: "Détecter automatiquement un visage dans la vidéo"],
        "Target Video":         [.en: "Target Video",     .zhHans: "目标视频",    .zhHant: "目標視頻",    .ja: "対象動画",       .fr: "Vidéo cible"],
        "Write Title":          [.en: "Write Title",      .zhHans: "写入标题",    .zhHant: "寫入標題",    .ja: "書き込むタイトル", .fr: "Titre à écrire"],
        "Status":               [.en: "Status",           .zhHans: "处理状态",    .zhHant: "處理狀態",    .ja: "処理状況",       .fr: "Statut"],
        "Actions":              [.en: "Actions",          .zhHans: "操作",        .zhHant: "操作",        .ja: "操作",           .fr: "Actions"],
        "Clear Done":           [.en: "Clear Completed",  .zhHans: "清空已完成",  .zhHant: "清空已完成",  .ja: "完了済みを削除", .fr: "Effacer les terminés"],
        "Generate NFO":         [.en: "Generate NFO",     .zhHans: "一键生成 NFO", .zhHant: "一鍵生成 NFO", .ja: "NFO を生成",    .fr: "Générer les NFO"],
        "Remove Selected":      [.en: "Remove Selected Tasks", .zhHans: "移除选中的任务", .zhHant: "移除選中的任務", .ja: "選択したタスクを削除", .fr: "Supprimer les tâches sélectionnées"],
        "Auto Detect":          [.en: "(auto detect)",    .zhHans: "(自动识别)",  .zhHant: "(自動識別)",  .ja: "(自動検出)",     .fr: "(détection auto)"],
        "Waiting":              [.en: "Waiting",          .zhHans: "等待",        .zhHant: "等待",        .ja: "待機",           .fr: "En attente"],
        "Done":                 [.en: "Done",             .zhHans: "完成",        .zhHant: "完成",        .ja: "完了",           .fr: "Terminé"],
        "status.waiting":       [.en: "Waiting",          .zhHans: "等待处理",    .zhHant: "等待處理",    .ja: "待機中",         .fr: "En attente"],
        "status.processing":    [.en: "Processing…",      .zhHans: "处理中…",     .zhHant: "處理中…",     .ja: "処理中…",        .fr: "En cours…"],
        "status.success":       [.en: "✅ Success",        .zhHans: "✅ 成功",      .zhHant: "✅ 成功",      .ja: "✅ 完了",         .fr: "✅ Succès"],
        "status.error":         [.en: "❌ Failed",         .zhHans: "❌ 失败",      .zhHant: "❌ 失敗",      .ja: "❌ 失敗",         .fr: "❌ Échec"],
        "Theme":                [.en: "Theme",             .zhHans: "主题",        .zhHant: "主題",        .ja: "テーマ",         .fr: "Thème"],
        "Language":             [.en: "Language",          .zhHans: "语言",        .zhHant: "語言",        .ja: "言語",           .fr: "Langue"],
    ]
    return dict[key]?[lang] ?? key
}

enum AppTheme: String, CaseIterable {
    case system = "跟随系统"
    case light = "明亮"
    case dark = "黑暗"
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 2. 数据模型
struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    var fileURL: URL
    let addedDate = Date()
    var fileName: String { fileURL.lastPathComponent }
    var baseName: String { fileURL.deletingPathExtension().lastPathComponent }
    var folderURL: URL { fileURL.deletingLastPathComponent() }
}

struct Actor: Identifiable {
    let id = UUID()
    var name: String = ""
    var role: String = ""
}

struct NFOData {
    var title: String = ""
    var year: String = ""
    var genres: [String] = []
    var director: String = ""
    var actors: [Actor] = []
    var plot: String = ""
    var rating: Double = 0.0
    var posterURL: URL? = nil
    var autoExtractPoster: Bool = false
    var fanartURLs: [URL] = []
    var targetFilename: String = ""
}

struct QueueItem: Identifiable {
    let id = UUID()
    var video: VideoItem
    var nfoData: NFOData
    var status: QueueStatus = .waiting

    enum QueueStatus: String {
        case waiting = "等待处理"
        case processing = "处理中..."
        case success = "✅ 成功"
        case error = "❌ 失败"
    }
}

// MARK: - 3. 缓存管理器
class CacheManager {
    static let shared = CacheManager()
    func add(item: String, category: String) {
        guard !item.isEmpty else { return }
        let key = "cache_\(category)"
        var currentCache = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        currentCache[item, default: 0] += 1
        UserDefaults.standard.set(currentCache, forKey: key)
    }
    func getSorted(category: String) -> [String] {
        let key = "cache_\(category)"
        let cache = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        return cache.sorted { $0.value > $1.value }.map { $0.key }
    }
    func clear(category: String? = nil) {
        if let cat = category { UserDefaults.standard.removeObject(forKey: "cache_\(cat)") }
        else {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("cache_") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - 4. 全局状态
class AppState: ObservableObject {
    @Published var importedVideos: [VideoItem] = []
    @Published var queue: [QueueItem] = []
    @Published var thumbnailsCache: [URL: NSImage] = [:]

    @Published var languageStr: String = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.zhHans.rawValue {
        didSet { UserDefaults.standard.set(languageStr, forKey: "appLanguage") }
    }
    var lang: AppLanguage { AppLanguage(rawValue: languageStr) ?? .zhHans }

    enum SortOption { case added, name }
    @Published var sortOption: SortOption = .added

    func toggleSort() {
        sortOption = sortOption == .added ? .name : .added
        applySort()
    }
    
    private func applySort() {
        if sortOption == .name {
            importedVideos.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        } else {
            importedVideos.sort { $0.addedDate < $1.addedDate }
        }
    }

    func importFiles(urls: [URL]) {
        for url in urls {
            if ["mp4", "mkv", "mov", "avi", "m4v"].contains(url.pathExtension.lowercased()) {
                if !importedVideos.contains(where: { $0.fileURL == url }) {
                    importedVideos.append(VideoItem(fileURL: url))
                }
            }
        }
        applySort()
    }

    func addToQueue(videos: [VideoItem], data: NFOData) {
        for video in videos {
            CacheManager.shared.add(item: data.director, category: "director")
            data.genres.forEach { CacheManager.shared.add(item: $0, category: "genre") }
            data.actors.forEach { CacheManager.shared.add(item: $0.name, category: "actor") }
            queue.append(QueueItem(video: video, nfoData: data))
        }
    }

    func processQueue() {
        Task {
            for index in queue.indices {
                if queue[index].status == .waiting {
                    await MainActor.run { queue[index].status = .processing }
                    await processItem(at: index)
                }
            }
        }
    }

    func loadThumbnail(for url: URL) async {
        if thumbnailsCache[url] != nil { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        do {
            let duration = try await asset.load(.duration)
            let time = CMTime(seconds: min(15.0, duration.seconds / 2.0), preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
                await MainActor.run { self.thumbnailsCache[url] = nsImage }
            }
        } catch {}
    }

    private func processItem(at index: Int) async {
        let item = queue[index]
        var video = item.video
        let data = item.nfoData
        let fm = FileManager.default

        if !data.targetFilename.isEmpty && data.targetFilename != video.baseName {
            let newURL = video.folderURL.appendingPathComponent("\(data.targetFilename).\(video.fileURL.pathExtension)")
            do {
                try fm.moveItem(at: video.fileURL, to: newURL)
                video.fileURL = newURL
                await MainActor.run {
                    if let vIdx = self.importedVideos.firstIndex(where: { $0.id == video.id }) {
                        self.importedVideos[vIdx] = video
                        self.applySort()
                    }
                }
            } catch { print("重命名失败: \(error)") }
        }

        var xmlElements: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>", "<movie>"]
        let finalTitle = data.title.isEmpty ? video.baseName : data.title
        xmlElements.append("    <title>\(finalTitle)</title>")
        if !data.year.isEmpty { xmlElements.append("    <year>\(data.year)</year>") }
        if data.rating > 0 { xmlElements.append("    <userrating>\(String(format: "%.1f", data.rating))</userrating>") }
        if !data.director.isEmpty { xmlElements.append("    <director>\(data.director)</director>") }
        if !data.plot.isEmpty { xmlElements.append("    <plot>\(data.plot)</plot>") }
        for genre in data.genres { xmlElements.append("    <genre>\(genre)</genre>") }

        for actor in data.actors {
            let cleanName = actor.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanRole = actor.role.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty {
                var actorXml = "    <actor>\n        <name>\(cleanName)</name>"
                if !cleanRole.isEmpty { actorXml += "\n        <role>\(cleanRole)</role>" }
                actorXml += "\n    </actor>"
                xmlElements.append(actorXml)
            }
        }

        let posterTargetURL = video.folderURL.appendingPathComponent("\(video.baseName)-poster.jpg")
        var posterGenerated = false
        if let posterURL = data.posterURL {
            if posterURL.deletingLastPathComponent().standardized == video.folderURL.standardized {
                xmlElements.append("    <thumb aspect=\"poster\">\(posterURL.lastPathComponent)</thumb>")
                posterGenerated = false
            } else {
                try? fm.removeItem(at: posterTargetURL)
                if (try? fm.copyItem(at: posterURL, to: posterTargetURL)) != nil { posterGenerated = true }
            }
        } else if data.autoExtractPoster {
            posterGenerated = await extractAndSmartCropPoster(from: video.fileURL, to: posterTargetURL)
        }
        if posterGenerated { xmlElements.append("    <thumb aspect=\"poster\">\(posterTargetURL.lastPathComponent)</thumb>") }

        if !data.fanartURLs.isEmpty {
            xmlElements.append("    <fanart>")
            for (i, fanartURL) in data.fanartURLs.enumerated() {
                if fanartURL.deletingLastPathComponent().standardized == video.folderURL.standardized {
                    xmlElements.append("        <thumb>\(fanartURL.lastPathComponent)</thumb>")
                } else {
                    let targetExt = fanartURL.pathExtension
                    let suffix = i == 0 ? "-fanart" : "-fanart\(i+1)"
                    let targetURL = video.folderURL.appendingPathComponent("\(video.baseName)\(suffix).\(targetExt)")
                    try? fm.removeItem(at: targetURL)
                    if (try? fm.copyItem(at: fanartURL, to: targetURL)) != nil {
                        xmlElements.append("        <thumb>\(targetURL.lastPathComponent)</thumb>")
                    }
                }
            }
            xmlElements.append("    </fanart>")
        }
        xmlElements.append("</movie>")

        let finalXML = xmlElements.joined(separator: "\n")
        let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo")
        do {
            try finalXML.write(to: nfoURL, atomically: true, encoding: .utf8)
            await MainActor.run { self.queue[index].status = .success }
        } catch { await MainActor.run { self.queue[index].status = .error } }
    }

    private func extractAndSmartCropPoster(from videoURL: URL, to destURL: URL) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let durationObj = try? await asset.load(.duration) else { return false }
        let durationSec = durationObj.seconds
        guard durationSec > 0 && !durationSec.isNaN else { return false }
        var targetTimes = [15.0, 10.0, 20.0, 30.0].filter { $0 < durationSec }
        if targetTimes.isEmpty { targetTimes.append(durationSec / 2.0) }
        for timeSec in targetTimes {
            let time = CMTime(seconds: timeSec, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time),
               let croppedImage = smartCropTo2x3(cgImage: cgImage) {
                let rep = NSBitmapImageRep(cgImage: croppedImage)
                if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    if (try? data.write(to: destURL)) != nil { return true }
                }
            }
        }
        return false
    }

    private func smartCropTo2x3(cgImage: CGImage) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let targetRatio: CGFloat = 2.0 / 3.0
        var faceCenter = CGPoint(x: width / 2.0, y: height / 2.0)
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        if let results = request.results, let face = results.first {
            let bbox = face.boundingBox
            faceCenter = CGPoint(x: bbox.midX * width, y: (1.0 - bbox.midY) * height)
        }
        var cropWidth: CGFloat
        var cropHeight: CGFloat
        if (width / height) > targetRatio {
            cropHeight = height; cropWidth = height * targetRatio
        } else {
            cropWidth = width; cropHeight = width / targetRatio
        }
        let idealOriginX = faceCenter.x - (cropWidth / 2.0)
        let idealOriginY = faceCenter.y - (cropHeight / 2.0)
        let originX = max(0, min(idealOriginX, width - cropWidth))
        let originY = max(0, min(idealOriginY, height - cropHeight))
        return cgImage.cropping(to: CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight))
    }
}

// MARK: - 5. 视频缩略图组件
struct ThumbnailStack: View {
    let videos: [VideoItem]
    let cache: [URL: NSImage]
    private let cardW: CGFloat = 112
    private let cardH: CGFloat = 72
    private let stackOffset: CGFloat = 10

    var body: some View {
        let count = min(videos.count, 3)
        let containerW = cardW + CGFloat(count - 1) * stackOffset
        let containerH = cardH + CGFloat(count - 1) * (stackOffset * 0.4)

        ZStack(alignment: .topLeading) {
            ForEach((0..<count).reversed(), id: \.self) { index in
                thumbnailCard(for: videos[index])
                    .frame(width: cardW, height: cardH)
                    .offset(x: CGFloat(index) * stackOffset, y: CGFloat(index) * (stackOffset * 0.4))
            }
        }
        .frame(width: containerW, height: containerH, alignment: .topLeading)
    }

    @ViewBuilder
    private func thumbnailCard(for video: VideoItem) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.windowBackgroundColor))
            .overlay {
                if let img = cache[video.fileURL] {
                    Image(nsImage: img).resizable().scaledToFill().clipped()
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 1, y: 2)
    }
}

// MARK: - 6. 编辑器头部信息区
struct EditorHeaderView: View {
    let selectedVideos: [VideoItem]
    let cache: [URL: NSImage]
    let lang: AppLanguage
    @Binding var targetFilename: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            if selectedVideos.isEmpty {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                    .frame(width: 112, height: 72)
                Text(tr("Select to Edit", lang: lang))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ThumbnailStack(videos: selectedVideos, cache: cache)
                VStack(alignment: .leading, spacing: 6) {
                    if selectedVideos.count == 1 {
                        Text(tr("Rename File", lang: lang)).font(.caption).foregroundStyle(.secondary)
                        TextField(tr("No Extension", lang: lang), text: $targetFilename)
                            .textFieldStyle(.roundedBorder).font(.body)
                    } else {
                        Label("\(tr("Selected", lang: lang)) \(selectedVideos.count) \(tr("Videos", lang: lang))", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.primary)
                        Text(selectedVideos.map(\.baseName).joined(separator: "、"))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(height: 100).background(.bar)
    }
}

// MARK: - 7. ContentView
struct ContentView: View {
    @StateObject private var appState = AppState()
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }

    var body: some View {
        TabView {
            EditorView()
                .environmentObject(appState)
                .tabItem { Label(tr("Editor & Import", lang: lang), systemImage: "square.and.pencil") }

            QueueView()
                .environmentObject(appState)
                .tabItem { Label("\(tr("Process Queue", lang: lang)) (\(appState.queue.count))", systemImage: "list.bullet.rectangle") }
        }
        .frame(minWidth: 1080, minHeight: 720)
    }
}

// MARK: - 8. EditorView
struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedVideoIDs = Set<UUID>()
    @State private var isImportingVideos = false
    @State private var nfoTemplate = NFOData()
    @State private var currentGenreInput: String = ""
    @State private var isSelectingPoster = false
    @State private var isSelectingFanart = false

    let importNotifier = NotificationCenter.default.publisher(for: .init("TriggerImportVideos"))
    let addQueueNotifier = NotificationCenter.default.publisher(for: .init("TriggerAddToQueue"))

    let years = Array(1900...Calendar.current.component(.year, from: Date()) + 5).reversed()

    private var selectedVideos: [VideoItem] { appState.importedVideos.filter { selectedVideoIDs.contains($0.id) } }

    var body: some View {
        // 🌟 解锁 columnVisibility 控制权，并移除了自定义的 ToolbarItem
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(importNotifier) { _ in isImportingVideos = true }
        .onReceive(addQueueNotifier) { _ in submitToQueue() }
        .onChange(of: selectedVideoIDs) { _, newSelection in handleSelectionChange(newSelection) }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            ZStack {
                List(selection: $selectedVideoIDs) {
                    ForEach(appState.importedVideos) { video in
                        Text(video.fileName)
                            .lineLimit(2).truncationMode(.middle).tag(video.id)
                    }
                    .onDelete { indices in
                        let idsToDelete = indices.map { appState.importedVideos[$0].id }
                        appState.importedVideos.remove(atOffsets: indices)
                        idsToDelete.forEach { selectedVideoIDs.remove($0) }
                    }
                    
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 600)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedVideoIDs.removeAll() }
                }
                .contextMenu(forSelectionType: VideoItem.ID.self) { items in
                    if !items.isEmpty {
                        Button(tr("Reveal in Finder", lang: lang)) {
                            let urls = appState.importedVideos.filter { items.contains($0.id) }.map { $0.fileURL }
                            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                        }
                        Divider()
                        Button(tr("Remove from List", lang: lang), role: .destructive) {
                            withAnimation {
                                appState.importedVideos.removeAll { items.contains($0.id) }
                                items.forEach { selectedVideoIDs.remove($0) }
                            }
                        }
                    }
                }
                
                if appState.importedVideos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.tertiary)
                        Text(tr("Drop Videos Here", lang: lang)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { selectedVideoIDs.removeAll() })
            
            Divider()
            
            // 🌟 将控制和排序按钮稳稳地放在底部工具栏
            HStack(spacing: 12) {
                Button { isImportingVideos = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(tr("Import", lang: lang))
                
                Button { withAnimation { appState.toggleSort() } } label: {
                    Image(systemName: appState.sortOption == .added ? "textformat.abc" : "clock")
                }
                .buttonStyle(.borderless)
                .help(appState.sortOption == .added ? tr("Sort by Name", lang: lang) : tr("Sort by Added", lang: lang))
                
                Spacer()
                
                if !selectedVideoIDs.isEmpty {
                    Text("\(tr("Selected Count", lang: lang)) \(selectedVideoIDs.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
        .navigationTitle(tr("Import Videos", lang: lang))
        .frame(minWidth: 220, idealWidth: 260)
        // 🌟 已删除产生冲突的 .toolbar { ToolbarItem(...) }，完全交给系统渲染原生侧边栏按钮
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let group = DispatchGroup(); var collectedURLs: [URL] = []; let lock = NSLock()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { lock.lock(); collectedURLs.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { appState.importFiles(urls: collectedURLs) }
            return true
        }
        .fileImporter(isPresented: $isImportingVideos, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { appState.importFiles(urls: urls) }
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            EditorHeaderView(selectedVideos: selectedVideos, cache: appState.thumbnailsCache, lang: lang, targetFilename: $nfoTemplate.targetFilename)
            Divider()
            ScrollView { formContent.padding() }
        }
        .fileImporter(isPresented: $isSelectingPoster, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { nfoTemplate.posterURL = urls.first }
        }
        .fileImporter(isPresented: $isSelectingFanart, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { nfoTemplate.fanartURLs = urls }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label(tr("Basic Info", lang: lang), systemImage: "info.circle").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledTextField(label: tr("Title", lang: lang), text: $nfoTemplate.title)
                    HStack(spacing: 12) {
                        Text(tr("Year", lang: lang)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        Picker("", selection: $nfoTemplate.year) {
                            Text(tr("Leave Empty", lang: lang)).tag("")
                            ForEach(years, id: \.self) { year in Text(String(year)).tag(String(year)) }
                        }.pickerStyle(.menu).frame(width: 110)
                        Spacer()
                    }
                    DirectorField(director: $nfoTemplate.director, lang: lang)
                    GenreField(genres: $nfoTemplate.genres, currentInput: $currentGenreInput, lang: lang)
                }.padding(.top, 8)
            }

            GroupBox(label: Label("\(tr("Rating", lang: lang)): \(String(format: "%.1f", nfoTemplate.rating))", systemImage: "star.circle").font(.headline)) {
                HStack(spacing: 12) {
                    Slider(value: $nfoTemplate.rating, in: 0...10, step: 0.1)
                    if nfoTemplate.rating > 0 {
                        Button(tr("Clear Rating", lang: lang)) { nfoTemplate.rating = 0 }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)
            }

            GroupBox(label: Label(tr("Plot", lang: lang), systemImage: "text.alignleft").font(.headline)) {
                TextEditor(text: $nfoTemplate.plot)
                    .frame(minHeight: 90, maxHeight: 160).font(.body)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    .padding(.top, 8)
            }

            GroupBox(label: Label(tr("Actors", lang: lang), systemImage: "person.2").font(.headline)) {
                VStack(spacing: 8) {
                    ForEach($nfoTemplate.actors) { $actor in
                        ActorRow(actor: $actor, lang: lang) { nfoTemplate.actors.removeAll { $0.id == actor.id } }
                    }
                    Button { nfoTemplate.actors.append(Actor()) } label: { Label(tr("Add Actor", lang: lang), systemImage: "person.badge.plus") }
                    .buttonStyle(.borderless).padding(.top, 4)
                }.padding(.top, 8)
            }

            GroupBox(label: Label(tr("Gallery", lang: lang), systemImage: "photo.on.rectangle").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(tr("Poster", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        Text(nfoTemplate.posterURL?.lastPathComponent ?? tr("Not Selected", lang: lang))
                            .foregroundStyle(nfoTemplate.posterURL == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(tr("Choose", lang: lang)) { isSelectingPoster = true }
                        if nfoTemplate.posterURL != nil {
                            Button(tr("Remove", lang: lang)) { nfoTemplate.posterURL = nil }.foregroundStyle(.red).buttonStyle(.borderless)
                        }
                    }
                    if nfoTemplate.posterURL == nil {
                        Toggle(tr("Auto Extract Poster", lang: lang), isOn: $nfoTemplate.autoExtractPoster).font(.caption).foregroundStyle(.secondary).padding(.leading, 48)
                    }
                    Divider()
                    HStack {
                        Text(tr("Fanart", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        Text(nfoTemplate.fanartURLs.isEmpty ? tr("Not Selected", lang: lang) : "\(nfoTemplate.fanartURLs.count) \(tr("Selected N Images", lang: lang))")
                            .foregroundStyle(nfoTemplate.fanartURLs.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button(tr("Choose", lang: lang)) { isSelectingFanart = true }
                        if !nfoTemplate.fanartURLs.isEmpty {
                            Button(tr("Remove", lang: lang)) { nfoTemplate.fanartURLs.removeAll() }.foregroundStyle(.red).buttonStyle(.borderless)
                        }
                    }
                }.padding(.top, 8)
            }

            HStack {
                Spacer()
                if #available(macOS 15.0, *) {
                    Button { submitToQueue() } label: { Label(tr("Add to Queue", lang: lang), systemImage: "arrow.right.square.fill") }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .disabled(selectedVideoIDs.isEmpty).keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button { submitToQueue() } label: { Label(tr("Add to Queue", lang: lang), systemImage: "arrow.right.square.fill").padding(.horizontal, 24).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).clipShape(Capsule())
                    .disabled(selectedVideoIDs.isEmpty).keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    private func submitToQueue() { appState.addToQueue(videos: selectedVideos, data: nfoTemplate) }

    private func handleSelectionChange(_ newSelection: Set<UUID>) {
        Task {
            for id in newSelection {
                if let video = appState.importedVideos.first(where: { $0.id == id }) {
                    await appState.loadThumbnail(for: video.fileURL)
                }
            }
        }
        if newSelection.count == 1, let video = appState.importedVideos.first(where: { $0.id == newSelection.first! }) {
            nfoTemplate.targetFilename = video.baseName; parseExistingNFO(for: video)
        } else { nfoTemplate = NFOData() }
    }

    private func parseExistingNFO(for video: VideoItem) {
        let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo")
        guard FileManager.default.fileExists(atPath: nfoURL.path),
              let xmlDoc = try? XMLDocument(contentsOf: nfoURL, options: []), let root = xmlDoc.rootElement() else { return }
        nfoTemplate.title = root.elements(forName: "title").first?.stringValue ?? ""
        nfoTemplate.year = root.elements(forName: "year").first?.stringValue ?? ""
        nfoTemplate.director = root.elements(forName: "director").first?.stringValue ?? ""
        nfoTemplate.plot = root.elements(forName: "plot").first?.stringValue ?? ""
        if let r = Double(root.elements(forName: "userrating").first?.stringValue ?? "") { nfoTemplate.rating = r }
        nfoTemplate.genres = root.elements(forName: "genre").compactMap { $0.stringValue }
        nfoTemplate.actors = root.elements(forName: "actor").compactMap { node in
            let name = node.elements(forName: "name").first?.stringValue ?? ""
            guard !name.isEmpty else { return nil }
            return Actor(name: name, role: node.elements(forName: "role").first?.stringValue ?? "")
        }
    }
}

// MARK: - 9. 拆分的子组件
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
            TextField(label, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

struct DirectorField: View {
    @Binding var director: String
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledTextField(label: tr("Director", lang: lang), text: $director)
            let cached = CacheManager.shared.getSorted(category: "director").prefix(10)
            if !cached.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(cached), id: \.self) { name in ChipButton(title: name) { director = name } }
                    }.padding(.leading, 62)
                }
            }
        }
    }
}

struct GenreField: View {
    @Binding var genres: [String]
    @Binding var currentInput: String
    let lang: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(tr("Genres", lang: lang)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                TextField(tr("Add Genre Hint", lang: lang), text: $currentInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let t = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty && !genres.contains(t) { genres.append(t) }
                        currentInput = ""
                    }
            }
            if !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(genres, id: \.self) { genre in
                            HStack(spacing: 4) {
                                Text(genre).font(.subheadline)
                                Button { genres.removeAll { $0 == genre } } label: { Image(systemName: "xmark.circle.fill").font(.caption) }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Color.accentColor.opacity(0.12)).clipShape(Capsule())
                        }
                    }.padding(.leading, 62)
                }
            }
            let cachedGenres = CacheManager.shared.getSorted(category: "genre")
            let suggestions = cachedGenres.filter { !genres.contains($0) }.prefix(15)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(tr("Quick Add", lang: lang)).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(suggestions), id: \.self) { g in ChipButton(title: g) { genres.append(g) } }
                    }.padding(.leading, 62)
                }
            }
        }
    }
}

struct ActorRow: View {
    @Binding var actor: Actor
    let lang: AppLanguage
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(tr("Actor Name", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                TextField(tr("Actor Name PH", lang: lang), text: $actor.name).textFieldStyle(.roundedBorder)
                Menu { ForEach(CacheManager.shared.getSorted(category: "actor").prefix(10), id: \.self) { ca in Button(ca) { actor.name = ca } } }
                label: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28)
                Button(action: onDelete) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(tr("Actor Role", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                TextField(tr("Actor Role PH", lang: lang), text: $actor.role).textFieldStyle(.roundedBorder)
                Menu {
                    Button(tr("Lead Male", lang: lang))   { actor.role = tr("Lead Male", lang: lang) }
                    Button(tr("Lead Female", lang: lang)) { actor.role = tr("Lead Female", lang: lang) }
                    Button(tr("Supporting", lang: lang))  { actor.role = tr("Supporting", lang: lang) }
                } label: { Image(systemName: "list.bullet.circle").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28)
                Color.clear.frame(width: 28, height: 1)
            }
        }
        .padding(10).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChipButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(Color.secondary.opacity(0.12)).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - 10. 设置视图
struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    private var appThemeBinding: Binding<AppTheme> { Binding(get: { AppTheme(rawValue: appThemeRaw) ?? .system }, set: { appThemeRaw = $0.rawValue }) }

    var body: some View {
        Form {
            Section {
                Picker(tr("Theme Setting", lang: lang), selection: appThemeBinding) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in Text(theme.rawValue).tag(theme as AppTheme) }
                }
                Picker(tr("App Language", lang: lang), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { l in Text(l.rawValue).tag(l.rawValue) }
                }
            } header: {
                Text(tr("Appearance & Lang", lang: lang)).font(.headline)
            }

            Section {
                Text(tr("Cache Hint", lang: lang)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(tr("Clear Directors", lang: lang)) { CacheManager.shared.clear(category: "director") }
                    Button(tr("Clear Genres", lang: lang)) { CacheManager.shared.clear(category: "genre") }
                    Button(tr("Clear Actors", lang: lang)) { CacheManager.shared.clear(category: "actor") }
                }
                Button(tr("Clear All", lang: lang), role: .destructive) { CacheManager.shared.clear() }
            } header: {
                Text(tr("Cache Management", lang: lang)).font(.headline)
            }
        }
        .formStyle(.grouped).padding().frame(width: 480, height: 320)
    }
}

// MARK: - 11. 处理序列视图
struct QueueView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }

    var body: some View {
        VStack(spacing: 0) {
            Table(appState.queue) {
                TableColumn(tr("Target Video", lang: lang)) { item in
                    Text(item.video.fileName).lineLimit(1).truncationMode(.middle)
                }
                TableColumn(tr("Write Title", lang: lang)) { item in
                    Text(item.nfoData.title.isEmpty ? tr("Auto Detect", lang: lang) : item.nfoData.title)
                        .lineLimit(1).foregroundStyle(item.nfoData.title.isEmpty ? .secondary : .primary)
                }
                TableColumn(tr("Status", lang: lang)) { item in
                    Text(statusLabel(item.status, lang: lang)).foregroundStyle(statusColor(item.status)).fontWeight(.medium)
                }
                TableColumn(tr("Actions", lang: lang)) { item in
                    Button { appState.queue.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.red).disabled(item.status == .processing)
                }.width(60)
            }
            .contextMenu(forSelectionType: QueueItem.ID.self) { items in
                Button(tr("Reveal in Finder", lang: lang)) {
                    let urls = appState.queue.filter { items.contains($0.id) }.map { $0.video.fileURL }
                    if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                }
                Divider()
                Button(tr("Remove Selected", lang: lang), role: .destructive) { appState.queue.removeAll { items.contains($0.id) } }
            }

            Divider()

            HStack {
                Button(tr("Clear Done", lang: lang)) { appState.queue.removeAll { $0.status == .success } }
                .disabled(appState.queue.allSatisfy { $0.status != .success })

                Spacer()

                let waiting = appState.queue.filter { $0.status == .waiting }.count
                let done = appState.queue.filter { $0.status == .success }.count
                if !appState.queue.isEmpty {
                    Text("\(tr("Waiting", lang: lang)) \(waiting) · \(tr("Done", lang: lang)) \(done)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                
                if #available(macOS 15.0, *) {
                    Button { appState.processQueue() } label: { Label(tr("Generate NFO", lang: lang), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.green)
                    .disabled(appState.queue.filter { $0.status == .waiting }.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                } else {
                    Button { appState.processQueue() } label: { Label(tr("Generate NFO", lang: lang), systemImage: "play.fill").padding(.horizontal, 28).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).clipShape(Capsule()).tint(.green)
                    .disabled(appState.queue.filter { $0.status == .waiting }.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }

    private func statusLabel(_ status: QueueItem.QueueStatus, lang: AppLanguage) -> String {
        switch status {
        case .waiting:    return tr("status.waiting", lang: lang)
        case .processing: return tr("status.processing", lang: lang)
        case .success:    return tr("status.success", lang: lang)
        case .error:      return tr("status.error", lang: lang)
        }
    }

    private func statusColor(_ status: QueueItem.QueueStatus) -> Color {
        switch status {
        case .success: return .green
        case .error: return .red
        case .processing: return .orange
        case .waiting: return .secondary
        }
    }
}
