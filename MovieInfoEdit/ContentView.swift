import SwiftUI
import UniformTypeIdentifiers
import Combine
import Foundation
import AVFoundation
import Vision
import AppKit
import QuickLook

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func applyGlassEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect)
        } else {
            self.background(.regularMaterial)
        }
    }
}

// MARK: - App Language & Localization
enum AppLanguage: String, CaseIterable {
    case en = "English"; case zhHans = "简体中文"; case zhHant = "繁體中文"; case ja = "日本語"; case fr = "Français"
}

func applyGlobalLanguage(_ lang: AppLanguage) {
    let code: String
    switch lang {
    case .en: code = "en"; case .zhHans: code = "zh-Hans"; case .zhHant: code = "zh-Hant"; case .ja: code = "ja"; case .fr: code = "fr"
    }
    UserDefaults.standard.set([code], forKey: "AppleLanguages")
}

func tr(_ key: String, lang: AppLanguage) -> String {
    let dict: [String: [AppLanguage: String]] = [
        "Editor & Import":      [.en: "Editor",           .zhHans: "编辑与导入",  .zhHant: "編輯與導入",  .ja: "編集",          .fr: "Éditeur"],
        "Process Queue":        [.en: "Queue",             .zhHans: "处理序列",    .zhHant: "處理序列",    .ja: "キュー",        .fr: "File"],
        "Import Videos":        [.en: "Import Videos",    .zhHans: "导入视频",    .zhHant: "導入視頻",    .ja: "動画を読み込む", .fr: "Importer vidéos"],
        "Open Recent":          [.en: "Open Recent",      .zhHans: "打开最近",    .zhHant: "打開最近",    .ja: "最近使った項目", .fr: "Ouvrir récent"],
        "No Recent Files":      [.en: "No Recent Files",  .zhHans: "无最近文件",  .zhHant: "無最近文件",  .ja: "最近のファイルなし", .fr: "Aucun fichier récent"],
        "Process":              [.en: "Process",          .zhHans: "处理",        .zhHant: "處理",        .ja: "処理",          .fr: "Traiter"],
        "Add to Queue":         [.en: "Add to Queue",     .zhHans: "加入序列",    .zhHant: "加入序列",    .ja: "キューに追加",   .fr: "Ajouter à la file"],
        "Basic Info":           [.en: "Basic Info",       .zhHans: "基础信息",    .zhHant: "基礎信息",    .ja: "基本情報",      .fr: "Infos de base"],
        "Title":                [.en: "Title",             .zhHans: "标题",        .zhHant: "標題",        .ja: "タイトル",      .fr: "Titre"],
        "Year":                 [.en: "Year",              .zhHans: "年份",        .zhHant: "年份",        .ja: "公開年",        .fr: "Année"],
        "Country":              [.en: "Country",          .zhHans: "国家地区",    .zhHant: "國家地區",    .ja: "制作国",        .fr: "Pays"],
        "Premiered":            [.en: "Premiered",        .zhHans: "首映日期",    .zhHant: "首映日期",    .ja: "公開日",        .fr: "Première"],
        "Director":             [.en: "Director",         .zhHans: "导演",        .zhHant: "導演",        .ja: "監督",          .fr: "Réalisateur"],
        "Studio":               [.en: "Studio",            .zhHans: "工作室",      .zhHant: "工作室",      .ja: "スタジオ",      .fr: "Studio"],
        "Genres":               [.en: "Genres",            .zhHans: "类型",        .zhHant: "類型",        .ja: "ジャンル",      .fr: "Genres"],
        "Actors":               [.en: "Actors",            .zhHans: "演员",        .zhHant: "演員",        .ja: "出演者",        .fr: "Acteurs"],
        "Plot":                 [.en: "Plot",              .zhHans: "剧情简介",    .zhHant: "劇情簡介",    .ja: "あらすじ",      .fr: "Synopsis"],
        "OCR":                  [.en: "OCR Extract",       .zhHans: "提取字幕 (OCR)",.zhHant: "提取字幕 (OCR)", .ja: "字幕抽出(OCR)", .fr: "Extraire (OCR)"],
        "Rating":               [.en: "Rating",            .zhHans: "评分",        .zhHant: "評分",        .ja: "評価",          .fr: "Note"],
        "Settings":             [.en: "Settings",         .zhHans: "设置",        .zhHant: "設置",        .ja: "設定",          .fr: "Paramètres"],
        "Appearance & Lang":    [.en: "Appearance & Language", .zhHans: "外观与语言", .zhHant: "外觀與語言", .ja: "外観と表示言語", .fr: "Apparence et langue"],
        "Theme Setting":        [.en: "Theme:",            .zhHans: "主题设定:",   .zhHant: "主題设定:",   .ja: "テーマ設定:",   .fr: "Thème :"],
        "App Language":         [.en: "App Language:",     .zhHans: "应用语言:",   .zhHant: "應用语言:",   .ja: "アプリ言語:",   .fr: "Langue :"],
        "Language Restart Hint": [.en: "Some native UI elements may require an app restart.", .zhHans: "部分系统原生界面需重启后完全生效。", .zhHant: "部分系統原生介面需重啟後完全生效。", .ja: "一部のシステムUIは再起動後に反映されます。", .fr: "Certains éléments natifs nécessitent un redémarrage."],
        "Cache Management":     [.en: "Cache Management", .zhHans: "缓存管理",    .zhHant: "緩存管理",    .ja: "キャッシュ管理", .fr: "Gestion du cache"],
        "Cache Hint":           [.en: "The app records directors, genres and actors for quick autocomplete.", .zhHans: "系统会自动记录导演、类型、演员等信息，下次输入时可快速补全。", .zhHant: "系統會自動記錄導演、類型、演員等資訊，下次輸入時可快速補全。", .ja: "監督・ジャンル・出演者の入力履歴を記録し、次回の入力補完に活用します。", .fr: "L'app enregistre les réalisateurs, genres et actors pour la saisie automatique."],
        "Clear Directors":      [.en: "Clear Directors",  .zhHans: "清除历史导演", .zhHant: "清除歷史导演", .ja: "監督履歴を削除", .fr: "Effacer réalisateurs"],
        "Clear Genres":         [.en: "Clear Genres",     .zhHans: "清除历史类型", .zhHant: "清除歷史类型", .ja: "ジャンル履歴を削除", .fr: "Effacer genres"],
        "Clear Actors":         [.en: "Clear Actors",     .zhHans: "清除历史演员", .zhHant: "清除歷史演员", .ja: "出演者履歴を削除", .fr: "Effacer acteurs"],
        "Clear All":            [.en: "⚠️ Clear All Records", .zhHans: "⚠️ 清除所有记录", .zhHant: "⚠️ 清除所有記錄", .ja: "⚠️ すべての履歴を削除", .fr: "⚠️ Tout effacer"],
        "Import":               [.en: "Import",            .zhHans: "导入",        .zhHant: "導入",        .ja: "読み込む",      .fr: "Importer"],
        "Remove from List":     [.en: "Remove from List", .zhHans: "从列表中移除", .zhHant: "從列表中移除", .ja: "リストから削除", .fr: "Retirer de la liste"],
        "Remove Selected":      [.en: "Remove Selected",   .zhHans: "移除所选",    .zhHant: "移除所選",    .ja: "選択したものを削除", .fr: "Supprimer la sélection"],
        "Reveal in Finder":     [.en: "Reveal in Finder", .zhHans: "在 Finder 中显示", .zhHant: "在 Finder 中顯示", .ja: "Finderで表示", .fr: "Afficher dans le Finder"],
        "Sort by Name":         [.en: "Sort by Name",     .zhHans: "按文件名排序", .zhHant: "按檔案名排序", .ja: "名前順に並べ替え", .fr: "Trier par nom"],
        "Sort by Added":        [.en: "Sort by Added",    .zhHans: "按导入顺序排序", .zhHant: "按導入順序排序", .ja: "追加順に並べ替え", .fr: "Trier par ajout"],
        "Toggle Sidebar":       [.en: "Toggle Sidebar",   .zhHans: "切换侧边栏",    .zhHant: "切換側邊栏",    .ja: "サイドバー切替", .fr: "Basculer la barre"],
        "Drop Videos Here":     [.en: "Drop video files here", .zhHans: "拖入视频文件", .zhHant: "拖入視頻文件", .ja: "動画をドロップ", .fr: "Déposez des vidéos ici"],
        "Selected Count":       [.en: "Selected",          .zhHans: "已选",        .zhHant: "已選",        .ja: "選択中",        .fr: "Sélectionnés"],
        "No Extension":         [.en: "No extension",      .zhHans: "无扩展名",    .zhHant: "無副檔名",    .ja: "拡張子なし",    .fr: "Sans extension"],
        "Select to Edit":       [.en: "Select a video on the left to start editing", .zhHans: "请在左侧选择视频以开始编辑", .zhHant: "請在左側選擇視頻以開始編輯", .ja: "左側で動画を選択して編集開始", .fr: "Sélectionnez une vidéo à gauche pour commencer"],
        "Selected":             [.en: "Selected",          .zhHans: "已选中",      .zhHant: "已選中",      .ja: "选择中",        .fr: "Sélectionné"],
        "Videos":               [.en: "videos",            .zhHans: "个视频",      .zhHant: "個視頻",      .ja: "本の動画",      .fr: "vidéos"],
        "Leave Empty":          [.en: "Leave empty",      .zhHans: "留空",        .zhHant: "留空",        .ja: "空欄のまま",    .fr: "Laisser vide"],
        "Add Genre Hint":       [.en: "Type and press Return to add", .zhHans: "输入影片类型 (回车添加)", .zhHant: "輸入影片類型 (回車添加)", .ja: "入力後Returnで追加", .fr: "Tapez et appuyez sur Entrée"],
        "Quick Add":            [.en: "Quick add:",       .zhHans: "快捷添加:",   .zhHant: "快捷添加:",   .ja: "クイック追加:", .fr: "Ajout rapide :"],
        "Clear Rating":         [.en: "Clear",            .zhHans: "清除",        .zhHant: "清除",        .ja: "クリア",        .fr: "Effacer"],
        "Actor Name":           [.en: "Name",             .zhHans: "姓名",        .zhHant: "姓名",        .ja: "氏名",          .fr: "Nom"],
        "Actor Role":           [.en: "Role",             .zhHans: "角色",        .zhHant: "角色",        .ja: "役名",          .fr: "Rôle"],
        "Actor Name PH":        [.en: "Actor name",       .zhHans: "演员姓名",    .zhHant: "演員姓名",    .ja: "俳優名",        .fr: "Nom de l'acteur"],
        "Actor Role PH":        [.en: "Character name",   .zhHans: "饰演角色",    .zhHant: "角色",        .ja: "キャラクター名", .fr: "Nom du personnage"],
        "Add Actor":            [.en: "Add Actor",        .zhHans: "添加演员",    .zhHant: "添加演員",    .ja: "出演者を追加",   .fr: "Ajouter un acteur"],
        "Lead Male":            [.en: "Male Lead",        .zhHans: "男主",        .zhHant: "男主",        .ja: "主演（男）",    .fr: "Rôle principal (H)"],
        "Lead Female":          [.en: "Female Lead",      .zhHans: "女主",        .zhHant: "女主",        .ja: "主演（女）",    .fr: "Rôle principal (F)"],
        "Supporting":           [.en: "Supporting",       .zhHans: "配角",        .zhHant: "配角",        .ja: "助演",          .fr: "Second rôle"],
        "Gallery":              [.en: "Poster & Fanart",  .zhHans: "本地图库",    .zhHant: "本地圖庫",    .ja: "ローカル画像",   .fr: "Images locales"],
        "Poster":               [.en: "Poster:",          .zhHans: "封面:",        .zhHant: "封面:",        .ja: "ポスター:",      .fr: "Affiche :"],
        "Fanart":               [.en: "Fanart:",          .zhHans: "背景:",        .zhHant: "背景:",        .ja: "ファンアート:",   .fr: "Fanart :"],
        "Not Selected":         [.en: "Not selected",     .zhHans: "未选择",      .zhHant: "未選擇",      .ja: "未選択",        .fr: "Non sélectionné"],
        "Selected N Images":    [.en: "images selected",  .zhHans: "张已选",      .zhHant: "張已選",      .ja: "枚選択中",      .fr: "images sélectionnées"],
        "Choose":               [.en: "Choose…",          .zhHans: "选择…",       .zhHant: "選擇…",       .ja: "選択…",         .fr: "Choisir…"],
        "Remove":               [.en: "Remove",           .zhHans: "移除",        .zhHant: "移除",        .ja: "削除",          .fr: "Supprimer"],
        "Target Video":         [.en: "Target Video",     .zhHans: "目标视频",    .zhHant: "目標視頻",    .ja: "対象動画",      .fr: "Vidéo cible"],
        "Write Title":          [.en: "Write Title",      .zhHans: "写入标题",    .zhHant: "寫入標題",    .ja: "書き込むタイトル", .fr: "Titre à écrire"],
        "Status":               [.en: "Status",           .zhHans: "处理状态",    .zhHant: "處理狀態",    .ja: "処理状況",      .fr: "Statut"],
        "Actions":              [.en: "Actions",          .zhHans: "操作",        .zhHant: "操作",        .ja: "操作",          .fr: "Actions"],
        "Clear Done":           [.en: "Clear Completed",  .zhHans: "清空已完成",  .zhHant: "清空已完成",  .ja: "完了済みを削除", .fr: "Effacer les terminés"],
        "Generate NFO":         [.en: "Generate NFO",     .zhHans: "一键生成 NFO", .zhHant: "一鍵生成 NFO", .ja: "NFO を生成",    .fr: "Générer les NFO"],
        "Remove Selected Tasks":[.en: "Remove Selected Tasks", .zhHans: "移除选中的任务", .zhHant: "移除選中的任務", .ja: "選択したタスクを削除", .fr: "Supprimer les tâches sélectionnées"],
        "Auto Detect":          [.en: "(auto detect)",    .zhHans: "(自动识别)",  .zhHant: "(自動識別)",  .ja: "(自動検出)",     .fr: "(détection auto)"],
        "Waiting":              [.en: "Waiting",          .zhHans: "等待",        .zhHant: "等待",        .ja: "待機",          .fr: "En attente"],
        "Done":                 [.en: "Done",             .zhHans: "完成",        .zhHant: "完成",        .ja: "完了",          .fr: "Terminé"],
        "status.waiting":       [.en: "Waiting",          .zhHans: "等待处理",    .zhHant: "等待處理",    .ja: "待機中",        .fr: "En attente"],
        "status.processing":    [.en: "Processing…",      .zhHans: "处理中…",     .zhHant: "處理中…",     .ja: "処理中…",        .fr: "En cours…"],
        "status.success":       [.en: "✅ Success",       .zhHans: "✅ 成功",      .zhHant: "✅ 成功",      .ja: "✅ 完了",        .fr: "✅ Succès"],
        "status.error":         [.en: "❌ Failed",        .zhHans: "❌ 失败",      .zhHant: "❌ 失敗",      .ja: "❌ 失敗",        .fr: "❌ Échec"],
        "Theme":                [.en: "Theme",             .zhHans: "主题",        .zhHant: "主題",        .ja: "テーマ",        .fr: "Thème"],
        "Language":             [.en: "Language",          .zhHans: "语言",        .zhHant: "語言",        .ja: "言語",          .fr: "Langue"],
        "Select Cover":         [.en: "Select",           .zhHans: "选择",        .zhHant: "選擇",        .ja: "選択",          .fr: "Choisir"],
        "Extracting...":        [.en: "Extracting...",    .zhHans: "正在提取...",  .zhHant: "正在提取...",  .ja: "抽出中...",      .fr: "Extraction..."],
        "Auto Extract Covers":  [.en: "Smart Extract",    .zhHans: "智能提取",    .zhHant: "智能提取",    .ja: "スマート抽出",   .fr: "Extraction Intelligente"],
        "File Name":            [.en: "File Name:",       .zhHans: "文件名称:",   .zhHant: "檔案名稱:",   .ja: "ファイル名:",   .fr: "Nom du fichier :"],
        "Duration":             [.en: "Duration:",        .zhHans: "总时长:",     .zhHant: "總時長:",     .ja: "再生時間:",     .fr: "Durée :"],
        "Extract More":         [.en: "Extract Deeper",   .zhHans: "深度提取",    .zhHant: "深度提取",    .ja: "さらに抽出",      .fr: "Extraire plus"],
    ]
    return dict[key]?[lang] ?? key
}

func formatDuration(_ seconds: Double) -> String {
    guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
    let h = Int(seconds) / 3600; let m = (Int(seconds) % 3600) / 60; let s = Int(seconds) % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) } else { return String(format: "%02d:%02d", m, s) }
}

enum AppTheme: String, CaseIterable {
    case system = "跟随系统"; case light = "明亮"; case dark = "黑暗"
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

// MARK: - Models
struct VideoItem: Identifiable, Hashable {
    let id = UUID(); var fileURL: URL; let addedDate = Date()
    var fileName: String { fileURL.lastPathComponent }
    var baseName: String { fileURL.deletingPathExtension().lastPathComponent }
    var folderURL: URL { fileURL.deletingLastPathComponent() }
}

struct Actor: Identifiable { let id = UUID(); var name: String = ""; var role: String = "" }

struct NFOData {
    var title: String = ""; var year: String = ""; var country: String = ""; var studio: String = ""
    var enablePremiered: Bool = false; var premieredDate: Date = Date()
    var genres: [String] = []; var director: String = ""; var actors: [Actor] = []; var plot: String = ""
    var rating: Double = 0.0; var posterURL: URL? = nil; var fanartURLs: [URL] = []; var targetFilename: String = ""
}

struct QueueItem: Identifiable {
    let id = UUID(); var video: VideoItem; var nfoData: NFOData; var status: QueueStatus = .waiting; var errorMessage: String = ""
    enum QueueStatus: String { case waiting = "等待处理"; case processing = "处理中..."; case success = "✅ 成功"; case error = "❌ 失败" }
}

actor DropCollector { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }

struct LoadedLocalImage: Identifiable { let id = UUID(); let url: URL; let image: NSImage }
struct ExtractedImage: Identifiable { let id = UUID(); let image: NSImage }

struct ImageOption: Identifiable {
    let id: String
    let url: URL?
    let image: NSImage
    var isExtracted: Bool = false
    var tempId: UUID? = nil
}

// MARK: - Cache Manager
class CacheManager {
    static let shared = CacheManager()
    private let cacheFileURL: URL = {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NFOEditor"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }()
    private var store: [String: [String: Int]] = [:]
    private init() { load() }
    private func load() { guard let data = try? Data(contentsOf: cacheFileURL), let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return }; store = decoded }
    private func save() { if let data = try? JSONEncoder().encode(store) { try? data.write(to: cacheFileURL, options: .atomic) } }
    func add(item: String, category: String) { guard !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store[category, default: [:]][item, default: 0] += 1; save() }
    func getSorted(category: String) -> [String] { let cache = store[category] ?? [:]; return cache.sorted { if $0.value == $1.value { return $0.key.localizedStandardCompare($1.key) == .orderedAscending }; return $0.value > $1.value }.map { $0.key } }
    func clear(category: String? = nil) { if let cat = category { store.removeValue(forKey: cat) } else { store.removeAll() }; save() }
}

// MARK: - App State
@Observable class AppState {
    var importedVideos: [VideoItem] = []; var queue: [QueueItem] = []
    var thumbnailsCache: [URL: NSImage] = [:]; var durationsCache: [URL: Double] = [:]
    var languageStr: String = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.zhHans.rawValue { didSet { UserDefaults.standard.set(languageStr, forKey: "appLanguage") } }
    var lang: AppLanguage { AppLanguage(rawValue: languageStr) ?? .zhHans }
    enum SortOption { case added, name }
    var sortOption: SortOption = .added
    
    func toggleSort() { sortOption = sortOption == .added ? .name : .added; applySort() }
    private func applySort() { if sortOption == .name { importedVideos.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending } } else { importedVideos.sort { $0.addedDate < $1.addedDate } } }

    func importFiles(urls: [URL]) {
        let supportedExts = ["mp4", "mkv", "mov", "avi", "m4v", "ts", "wmv", "flv", "m2ts", "webm", "iso", "rmvb"]
        for url in urls { if supportedExts.contains(url.pathExtension.lowercased()) { if !importedVideos.contains(where: { $0.fileURL == url }) { importedVideos.append(VideoItem(fileURL: url)) } } }
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
            let waitingIDs = queue.filter { $0.status == .waiting }.map { $0.id }
            for id in waitingIDs {
                guard let index = queue.firstIndex(where: { $0.id == id }) else { continue }
                await MainActor.run { queue[index].status = .processing }
                guard let currentIndex = queue.firstIndex(where: { $0.id == id }) else { continue }
                await processItem(at: currentIndex)
            }
        }
    }
    
    // Core Mod 3: OCR depth search parameter support
    func performOCR(on url: URL, times: [Double]) async -> String {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        guard let durationObj = try? await asset.load(.duration) else { return "" }
        let durationSec = durationObj.seconds
        let validTimes = times.filter { $0 < durationSec || durationSec.isNaN }
        var extractedLines = [String]()
        
        for t in validTimes {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                if let results = request.results {
                    let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    if !text.isEmpty { extractedLines.append(text) }
                }
            }
        }
        return extractedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadMetadata(for url: URL) async {
        if thumbnailsCache[url] != nil && durationsCache[url] != nil { return }
        let asset = AVURLAsset(url: url)
        do {
            let durationObj = try await asset.load(.duration)
            await MainActor.run { if !durationObj.seconds.isNaN { self.durationsCache[url] = durationObj.seconds } }
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 320, height: 320)
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: min(15.0, durationObj.seconds / 2.0), preferredTimescale: 600)) {
                await MainActor.run { self.thumbnailsCache[url] = NSImage(cgImage: cgImage, size: NSZeroSize) }
            }
        } catch {}
    }

    func extractMultipleCovers(from videoURL: URL, times: [Double]) async -> [ExtractedImage] {
        let asset = AVURLAsset(url: videoURL); let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        guard let durationObj = try? await asset.load(.duration) else { return [] }
        var results: [ExtractedImage] = []
        for timeSec in times.filter({ $0 < durationObj.seconds }) {
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: timeSec, preferredTimescale: 600)), let faceCropped = smartCropTo2x3(cgImage: cgImage) {
                results.append(ExtractedImage(image: NSImage(cgImage: faceCropped, size: NSZeroSize)))
            }
        }
        return results
    }

    private func xmlEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
              .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func processItem(at index: Int) async {
        let item = queue[index]; var video = item.video; let data = item.nfoData; let fm = FileManager.default
        if !data.targetFilename.isEmpty && data.targetFilename != video.baseName {
            let newURL = video.folderURL.appendingPathComponent("\(data.targetFilename).\(video.fileURL.pathExtension)")
            do { try fm.moveItem(at: video.fileURL, to: newURL); video.fileURL = newURL; await MainActor.run { if let vIdx = self.importedVideos.firstIndex(where: { $0.id == video.id }) { self.importedVideos[vIdx] = video; self.applySort() } } } catch {}
        }
        var xmlElements: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>", "<movie>"]; let finalTitle = data.title.isEmpty ? video.baseName : data.title
        xmlElements.append("    <title>\(xmlEscape(finalTitle))</title>")
        if !data.year.isEmpty { xmlElements.append("    <year>\(xmlEscape(data.year))</year>") }
        if data.enablePremiered { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; xmlElements.append("    <premiered>\(df.string(from: data.premieredDate))</premiered>") }
        if data.rating > 0 { xmlElements.append("    <userrating>\(String(format: "%.1f", data.rating))</userrating>") }
        if !data.country.isEmpty { xmlElements.append("    <country>\(xmlEscape(data.country))</country>") }
        if !data.studio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { xmlElements.append("    <studio>\(xmlEscape(data.studio.trimmingCharacters(in: .whitespacesAndNewlines)))</studio>") }
        if !data.director.isEmpty { xmlElements.append("    <director>\(xmlEscape(data.director))</director>") }
        if !data.plot.isEmpty { xmlElements.append("    <plot>\(xmlEscape(data.plot))</plot>") }
        for genre in data.genres { xmlElements.append("    <genre>\(xmlEscape(genre))</genre>") }
        for actor in data.actors { let cleanName = actor.name.trimmingCharacters(in: .whitespacesAndNewlines); let cleanRole = actor.role.trimmingCharacters(in: .whitespacesAndNewlines); if !cleanName.isEmpty { var actorXml = "    <actor>\n        <name>\(xmlEscape(cleanName))</name>"; if !cleanRole.isEmpty { actorXml += "\n        <role>\(xmlEscape(cleanRole))</role>" }; actorXml += "\n    </actor>"; xmlElements.append(actorXml) } }
        let posterTargetURL = video.folderURL.appendingPathComponent("\(video.baseName)-poster.jpg"); var posterGenerated = false
        if let posterURL = data.posterURL { if posterURL.deletingLastPathComponent().standardized == video.folderURL.standardized { xmlElements.append("    <thumb aspect=\"poster\">\(posterURL.lastPathComponent)</thumb>"); posterGenerated = false } else { try? fm.removeItem(at: posterTargetURL); do { try fm.copyItem(at: posterURL, to: posterTargetURL); posterGenerated = true } catch {} } }
        if posterGenerated { xmlElements.append("    <thumb aspect=\"poster\">\(posterTargetURL.lastPathComponent)</thumb>") }
        if !data.fanartURLs.isEmpty {
            xmlElements.append("    <fanart>")
            for (i, fanartURL) in data.fanartURLs.enumerated() {
                if fanartURL.deletingLastPathComponent().standardized == video.folderURL.standardized { xmlElements.append("        <thumb>\(fanartURL.lastPathComponent)</thumb>") } else { let suffix = i == 0 ? "-fanart" : "-fanart\(i+1)"; let targetURL = video.folderURL.appendingPathComponent("\(video.baseName)\(suffix).\(fanartURL.pathExtension)"); try? fm.removeItem(at: targetURL); do { try fm.copyItem(at: fanartURL, to: targetURL); xmlElements.append("        <thumb>\(targetURL.lastPathComponent)</thumb>") } catch {} }
            }
            xmlElements.append("    </fanart>")
        }
        xmlElements.append("</movie>")
        let finalXML = xmlElements.joined(separator: "\n"); let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo")
        do { try finalXML.write(to: nfoURL, atomically: true, encoding: .utf8); await MainActor.run { self.queue[index].status = .success } } catch { await MainActor.run { self.queue[index].status = .error; self.queue[index].errorMessage = "写入失败" } }
    }

    private func smartCropTo2x3(cgImage: CGImage) -> CGImage? {
        let width = CGFloat(cgImage.width); let height = CGFloat(cgImage.height); let targetRatio: CGFloat = 2.0 / 3.0; var faceCenter = CGPoint(x: width / 2.0, y: height / 2.0)
        let request = VNDetectFaceRectanglesRequest(); let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        if let results = request.results, let face = results.first { faceCenter = CGPoint(x: face.boundingBox.midX * width, y: (1.0 - face.boundingBox.midY) * height) } else { return nil }
        var cropWidth: CGFloat; var cropHeight: CGFloat
        if (width / height) > targetRatio { cropHeight = height; cropWidth = height * targetRatio } else { cropWidth = width; cropHeight = width / targetRatio }
        let originX = max(0, min(faceCenter.x - (cropWidth / 2.0), width - cropWidth)); let originY = max(0, min(faceCenter.y - (cropHeight / 2.0), height - cropHeight))
        return cgImage.cropping(to: CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight))
    }
}

// MARK: - Components

struct AmbilightThumbnail: View {
    let image: NSImage?
    var width: CGFloat
    var height: CGFloat
    var isStacked: Bool = false
    
    var body: some View {
        ZStack {
            if let image = image {
                // 1. Ambilight glow layer (reduced radius/scale to prevent clipping on the left edge)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    // Refined to avoid hard clipping "shadow" effect at the DetailView boundary
                    .blur(radius: isStacked ? 18 : 16)
                    .opacity(isStacked ? 0.6 : 0.8)
                    .brightness(0.13)
                    .saturation(1.5)
                    .scaleEffect(isStacked ? 1.05 : 1.1)
                    .offset(y: 2)

                // 2. Clear Original Image Layer
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: width, height: height)
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}

struct ThumbnailStack: View {
    let videos: [VideoItem]; let cache: [URL: NSImage]
    @State private var isHovered = false

    var body: some View {
        let count = min(videos.count, 4); let isSingle = count == 1
        let cardW: CGFloat = isSingle ? 160 : 140; let cardH: CGFloat = isSingle ? 100 : 90
        
        ZStack(alignment: .topLeading) {
            ForEach((0..<count).reversed(), id: \.self) { index in
                let img = cache[videos[index].fileURL]
                AmbilightThumbnail(image: img, width: cardW, height: cardH, isStacked: !isSingle)
                    .opacity(!isHovered && index == 3 ? 0 : 1)
                    .offset(x: xOffset(index: index, isHovered: isHovered, count: count), y: yOffset(index: index, isHovered: isHovered, count: count))
                    .zIndex(Double(4 - index))
                    .scaleEffect(isHovered && isSingle ? 1.05 : 1.0, anchor: .center)
            }
        }
        .frame(width: 200, height: 115, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    // Core Mod 2: Physics anchor calculation system
    private func xOffset(index: Int, isHovered: Bool, count: Int) -> CGFloat {
        if count == 1 { return 20 } // Adjusted inward to prevent left-side blur clip
        let baseIndex = min(count - 1, 2)
        let unhoveredX = 36 + CGFloat(baseIndex) * 8
        if !isHovered { return 36 + CGFloat(min(index, 2)) * 8 }
        else {
            let shift = CGFloat((count - 1) - index)
            return unhoveredX - shift * 16
        }
    }
    
    private func yOffset(index: Int, isHovered: Bool, count: Int) -> CGFloat {
        if count == 1 { return 10 }
        let baseIndex = min(count - 1, 2)
        let unhoveredY = 14 + CGFloat(baseIndex) * 3
        if !isHovered { return 14 + CGFloat(min(index, 2)) * 3 }
        else {
            let shift = CGFloat((count - 1) - index)
            return unhoveredY - shift * 6
        }
    }
}

struct VisualEffectHeader: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .titlebar; var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    func makeNSView(context: Context) -> NSVisualEffectView { let v = NSVisualEffectView(); v.material = material; v.blendingMode = blendingMode; v.state = .active; return v }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct EditorHeaderView: View {
    let selectedVideos: [VideoItem]
    let cache: [URL: NSImage]
    let durationsCache: [URL: Double]
    let lang: AppLanguage
    @Binding var targetFilename: String
    
    private var totalDuration: Double { selectedVideos.compactMap { durationsCache[$0.fileURL] }.reduce(0, +) }

    var body: some View {
        ZStack(alignment: .top) {
            
            // 1. Header Background
            // Cleaned up border logic, ensured no overlapping shadows
            Group {
                if #available(macOS 26.0, *) {
                    Color.white.opacity(0.25)
                        .glassEffect(.regular, in: .rect)
                } else {
                    ZStack {
                        VisualEffectHeader(material: .headerView, blendingMode: .withinWindow)
                        Color.black.opacity(0.02) // Subtle flat tint, avoids shadow buildup
                    }
                }
            }
            .frame(height: 180, alignment: .top)
            .ignoresSafeArea(.all, edges: .top)

            // 2. Content Layer
            Group {
                HStack(alignment: .center, spacing: 28) {
                    if selectedVideos.isEmpty {
                        ZStack(alignment: .center) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                                .frame(width: 160, height: 100)
                        }
                        .frame(width: 200, height: 115, alignment: .topLeading)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Select to Edit", lang: lang)).font(.headline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        
                    } else {
                        ThumbnailStack(videos: selectedVideos, cache: cache)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            if selectedVideos.count == 1 {
                                Text(tr("File Name", lang: lang)).font(.caption).foregroundStyle(.secondary)
                                TextField(tr("No Extension", lang: lang), text: $targetFilename)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                                    .font(.body)
                            } else {
                                Label("\(tr("Selected", lang: lang)) \(selectedVideos.count) \(tr("Videos", lang: lang))", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.primary)
                                Text(selectedVideos.map(\.baseName).joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                        
                        if totalDuration > 0 {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(tr("Duration", lang: lang)).font(.caption).foregroundStyle(.secondary)
                                Text(formatDuration(totalDuration)).font(.headline).monospacedDigit()
                            }
                            .padding(.leading, 10)
                        }
                    }
                }
                // INCREASED leading padding (was 20, now 32)
                // This ensures the ambilight blur from ThumbnailStack naturally fades
                // before it hits the left edge, preventing the "shadow block" clipping artifact.
                .padding(.leading, 32)
                .padding(.trailing, 20)
                .padding(.top, 46)
                .padding(.bottom, 16)
            }
            .frame(height: 180, alignment: .top)
        }
        // Prevents anything inside the header from casting a shadow OUTSIDE the header (into the sidebar)
        .clipped()
    }
}


@ViewBuilder
private func InteractiveImageCard(image: NSImage, width: CGFloat, height: CGFloat, isHovered: Bool, isSelected: Bool, lang: AppLanguage, onHoverChange: @escaping (Bool) -> Void, onAction: @escaping () -> Void) -> some View {
    ZStack(alignment: .center) {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: (isHovered || isSelected) ? 3 : 0))
        if isHovered { Button(isSelected ? tr("Remove", lang: lang) : tr("Select Cover", lang: lang), action: onAction).buttonStyle(.glass).transition(.opacity) }
    }.onHover { hover in withAnimation(.easeInOut(duration: 0.2)) { onHoverChange(hover) } }
}

struct GallerySection: View {
    @Binding var nfoData: NFOData; var videoURL: URL?; let lang: AppLanguage
    @State private var loadedLocalImages: [LoadedLocalImage] = []
    
    var body: some View {
        GroupBox(label: Label(tr("Gallery", lang: lang), systemImage: "photo.on.rectangle").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) { SmartPosterPicker(posterURL: $nfoData.posterURL, videoURL: videoURL, loadedLocalImages: $loadedLocalImages, lang: lang); Divider(); FanartPicker(fanartURLs: $nfoData.fanartURLs, videoURL: videoURL, loadedLocalImages: loadedLocalImages, lang: lang) }.padding(.top, 8)
        }
        // Swift 6 Compatibility
        .onChange(of: videoURL) { oldURL, newURL in loadLocalImages() }
        .onAppear { loadLocalImages() }
    }
    
    private func loadLocalImages() {
        guard let url = videoURL else { loadedLocalImages = []; return }
        let folder = url.deletingLastPathComponent(); let baseName = url.deletingPathExtension().lastPathComponent
        Task {
            if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let matchedURLs = files.filter { ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) && $0.lastPathComponent.contains(baseName) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                var loaded: [LoadedLocalImage] = []
                for file in matchedURLs { if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { loaded.append(LoadedLocalImage(url: file, image: img)) } }
                await MainActor.run { self.loadedLocalImages = loaded }
            } else { await MainActor.run { self.loadedLocalImages = [] } }
        }
    }
}

struct SmartPosterPicker: View {
    @Binding var posterURL: URL?; let videoURL: URL?; @Binding var loadedLocalImages: [LoadedLocalImage]; let lang: AppLanguage; @Environment(AppState.self) private var appState
    @State private var extractedImages: [ExtractedImage] = []; @State private var isExtracting = false; @State private var hoveredID: String? = nil; @State private var isSelectingFile = false; @State private var extractionPhase = 0
    @State private var previewSelectedID: String? = nil
    @State private var savedExtractedURLs: [UUID: URL] = [:]
    
    private var sortedOptions: [ImageOption] {
        var options: [ImageOption] = loadedLocalImages.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
        for ext in extractedImages {
            if let savedURL = savedExtractedURLs[ext.id] { options.append(ImageOption(id: ext.id.uuidString, url: savedURL, image: ext.image, isExtracted: true, tempId: ext.id)) }
            else { options.append(ImageOption(id: ext.id.uuidString, url: nil, image: ext.image, isExtracted: true, tempId: ext.id)) }
        }
        if let purl = posterURL, !options.contains(where: { $0.url == purl }) {
            if let data = try? Data(contentsOf: purl), let img = NSImage(data: data) { options.append(ImageOption(id: purl.absoluteString, url: purl, image: img, isExtracted: false)) }
        }
        let activeID = previewSelectedID ?? (posterURL != nil ? options.first(where: {$0.url == posterURL})?.id : nil)
        return options.sorted { a, b in if a.id == activeID { return true }; if b.id == activeID { return false }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Poster", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                if let url = posterURL { Text(url.lastPathComponent).font(.caption).foregroundStyle(.primary).lineLimit(1) } else { Text(tr("Not Selected", lang: lang)).font(.caption).foregroundStyle(.tertiary) }; Spacer()
                Button(action: startSmartExtraction) { if isExtracting { ProgressView().controlSize(.small) } else { Label(extractionPhase == 0 ? tr("Auto Extract Covers", lang: lang) : tr("Extract More", lang: lang), systemImage: "sparkles") } }.buttonStyle(.glass).controlSize(.small).disabled(isExtracting || videoURL == nil)
                Button(tr("Choose", lang: lang)) { isSelectingFile = true }.buttonStyle(.borderless)
                if posterURL != nil { Button(tr("Remove", lang: lang)) { removePoster() }.foregroundStyle(.red).buttonStyle(.borderless) }
            }
            if !sortedOptions.isEmpty {
                let isAnySelected = posterURL != nil
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: isAnySelected ? -100 : 16) {
                        ForEach(Array(sortedOptions.enumerated()), id: \.element.id) { index, option in
                            let isSelected = posterURL != nil && option.url == posterURL
                            let isAnimatingToSelect = previewSelectedID == option.id
                            InteractiveImageCard(image: option.image, width: 100, height: 150, isHovered: hoveredID == option.id, isSelected: isSelected || isAnimatingToSelect, lang: lang, onHoverChange: { hover in hoveredID = hover ? option.id : nil }) {
                                if isSelected {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { removePoster() }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { previewSelectedID = option.id }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            if option.isExtracted { saveImageAsPoster(option) } else { posterURL = option.url }
                                            previewSelectedID = nil
                                        }
                                    }
                                }
                            }.zIndex(isSelected || isAnimatingToSelect ? 10 : 1).scaleEffect(isAnySelected && !isSelected ? 0.5 : 1.0).opacity(isAnySelected && !isSelected ? 0 : 1)
                            // Core Mod 4: Cascade animation
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.05)),
                                removal: .opacity
                            ))
                        }
                    }.padding(.vertical, 8).padding(.horizontal, 4).animation(.spring(response: 0.4, dampingFraction: 0.7), value: posterURL)
                }.frame(height: 170)
            }
        }
        .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in if case .success(let urls) = result { posterURL = urls.first } }
        .onChange(of: videoURL) { oldURL, newURL in extractedImages = []; extractionPhase = 0; savedExtractedURLs.removeAll() }
    }

    private func startSmartExtraction() {
        guard let url = videoURL else { return }; isExtracting = true
        let times: [Double] = extractionPhase == 0 ? [5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0] : [90.0 + Double(extractionPhase - 1) * 120.0, 120.0 + Double(extractionPhase - 1) * 120.0, 180.0 + Double(extractionPhase - 1) * 120.0, 300.0 + Double(extractionPhase - 1) * 120.0]
        Task {
            let images = await appState.extractMultipleCovers(from: url, times: times)
            await MainActor.run { if extractionPhase == 0 { self.extractedImages = images } else { self.extractedImages.append(contentsOf: images) }; self.isExtracting = false; self.extractionPhase += 1 }
        }
    }

    private func saveImageAsPoster(_ option: ImageOption) {
        guard let videoURL = videoURL else { return }; let destURL = videoURL.deletingLastPathComponent().appendingPathComponent("\(videoURL.deletingPathExtension().lastPathComponent)-poster.jpg")
        guard let cgImage = option.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        if let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? data.write(to: destURL); if let tempId = option.tempId { savedExtractedURLs[tempId] = destURL }; self.posterURL = destURL
            if let idx = loadedLocalImages.firstIndex(where: { $0.url == destURL }) { loadedLocalImages[idx] = LoadedLocalImage(url: destURL, image: option.image) } else { loadedLocalImages.append(LoadedLocalImage(url: destURL, image: option.image)) }
            withAnimation { extractedImages.removeAll(where: { $0.id == option.tempId }) }
        }
    }

    private func removePoster() {
        if let url = posterURL, savedExtractedURLs.values.contains(url) {
            try? FileManager.default.removeItem(at: url)
            loadedLocalImages.removeAll { $0.url == url }
            savedExtractedURLs = savedExtractedURLs.filter { $0.value != url }
        }
        posterURL = nil
    }
}

struct FanartPicker: View {
    @Binding var fanartURLs: [URL]; let videoURL: URL?; let loadedLocalImages: [LoadedLocalImage]; let lang: AppLanguage
    @State private var isSelecting = false; @State private var hoveredID: String? = nil
    
    private var sortedOptions: [ImageOption] {
        var options: [ImageOption] = loadedLocalImages.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
        for url in fanartURLs { if !options.contains(where: { $0.url == url }) { if let data = try? Data(contentsOf: url), let img = NSImage(data: data) { options.append(ImageOption(id: url.absoluteString, url: url, image: img, isExtracted: false)) } } }
        return options.sorted { a, b in
            let aSel = a.url != nil && fanartURLs.contains(a.url!); let bSel = b.url != nil && fanartURLs.contains(b.url!)
            if aSel && !bSel { return true }; if !aSel && bSel { return false }; return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Fanart", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                Text(fanartURLs.isEmpty ? tr("Not Selected", lang: lang) : "\(fanartURLs.count) \(tr("Selected N Images", lang: lang))").foregroundStyle(fanartURLs.isEmpty ? .secondary : .primary); Spacer()
                Button(tr("Choose", lang: lang)) { isSelecting = true }; if !fanartURLs.isEmpty { Button(tr("Remove", lang: lang)) { fanartURLs.removeAll() }.foregroundStyle(.red).buttonStyle(.borderless) }
            }
            if !sortedOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(sortedOptions) { option in
                            let isSelected = option.url.map { fanartURLs.contains($0) } ?? false
                            InteractiveImageCard(image: option.image, width: 160, height: 90, isHovered: hoveredID == option.id, isSelected: isSelected, lang: lang, onHoverChange: { hover in hoveredID = hover ? option.id : nil }) {
                                if isSelected { fanartURLs.removeAll { $0 == option.url } } else if let url = option.url { fanartURLs.append(url) }
                            }.zIndex(isSelected ? 10 : 1)
                        }
                    }.padding(.vertical, 8).padding(.horizontal, 4).animation(.spring(response: 0.4, dampingFraction: 0.7), value: fanartURLs)
                }.frame(height: 110)
            }
        }
        .fileImporter(isPresented: $isSelecting, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in if case .success(let urls) = result { let newURLs = urls.filter { !fanartURLs.contains($0) }; fanartURLs.append(contentsOf: newURLs) } }
    }
}

struct LabeledTextField: View {
    let label: String; @Binding var text: String
    var body: some View { HStack(spacing: 12) { Text(label).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); TextField(label, text: $text).textFieldStyle(.roundedBorder) } }
}

struct DirectorField: View {
    @Binding var director: String; let lang: AppLanguage; private var cachedDirectors: [String] { Array(CacheManager.shared.getSorted(category: "director").prefix(10)) }
    @Namespace private var tagAnimation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledTextField(label: tr("Director", lang: lang), text: $director)
            if !cachedDirectors.isEmpty {
                HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: 50); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(cachedDirectors, id: \.self) { name in ChipButton(title: name) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { director = name } }.matchedGeometryEffect(id: name, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } }
            }
        }
    }
}

struct ActiveTag: View {
    let title: String; let onRemove: () -> Void; @State private var isHovered = false
    var body: some View { HStack(spacing: 4) { Text(title).font(.subheadline); Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption) }.buttonStyle(.plain) }.padding(.horizontal, 10).padding(.vertical, 4).background(Color.accentColor.opacity(isHovered ? 0.3 : 0.12)).clipShape(Capsule()).scaleEffect(isHovered ? 1.05 : 1.0).animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered).onHover { isHovered = $0 } }
}

struct GenreField: View {
    @Binding var genres: [String]; @Binding var currentInput: String; let lang: AppLanguage
    @Namespace private var tagAnimation
    private var suggestions: [String] { Array(CacheManager.shared.getSorted(category: "genre").filter { !genres.contains($0) }.prefix(30)) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) { Text(tr("Genres", lang: lang)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); TextField(tr("Add Genre Hint", lang: lang), text: $currentInput).textFieldStyle(.roundedBorder).onSubmit { let t = currentInput.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty && !genres.contains(t) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(t) } }; currentInput = "" } }
            if !genres.isEmpty { HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: 50); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(genres, id: \.self) { genre in ActiveTag(title: genre) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.removeAll { $0 == genre } } }.matchedGeometryEffect(id: genre, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } } }
            if !suggestions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(tr("Quick Add", lang: lang)).font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) { VStack(alignment: .leading, spacing: 6) { HStack(spacing: 6) { ForEach(suggestions.prefix(15), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } }; if suggestions.count > 15 { HStack(spacing: 6) { ForEach(Array(suggestions.dropFirst(15)), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } } } }.padding(.vertical, 8).padding(.horizontal, 2) }
                }
            }
        }
    }
}

struct ActorRow: View {
    @Binding var actor: Actor; let lang: AppLanguage; let onDelete: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { Text(tr("Actor Name", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing); TextField(tr("Actor Name PH", lang: lang), text: $actor.name).textFieldStyle(.roundedBorder); Menu { ForEach(Array(CacheManager.shared.getSorted(category: "actor").prefix(10)), id: \.self) { ca in Button(ca) { actor.name = ca } } } label: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28); Button(action: onDelete) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain) }
            HStack(spacing: 8) { Text(tr("Actor Role", lang: lang)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing); TextField(tr("Actor Role PH", lang: lang), text: $actor.role).textFieldStyle(.roundedBorder); Menu { Button(tr("Lead Male", lang: lang)) { actor.role = tr("Lead Male", lang: lang) }; Button(tr("Lead Female", lang: lang)) { actor.role = tr("Lead Female", lang: lang) }; Button(tr("Supporting", lang: lang)) { actor.role = tr("Supporting", lang: lang) } } label: { Image(systemName: "list.bullet.circle").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28); Color.clear.frame(width: 28, height: 1) }
        }.padding(10).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChipButton: View {
    let title: String; let action: () -> Void; @State private var isHovered = false
    var body: some View { Button(action: action) { Text(title).font(.caption).padding(.horizontal, 10).padding(.vertical, 4).background(isHovered ? Color.accentColor : Color.secondary.opacity(0.12)).foregroundStyle(isHovered ? Color.white : Color.primary).clipShape(Capsule()).scaleEffect(isHovered ? 1.05 : 1.0).animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered) }.buttonStyle(.plain).onHover { hover in isHovered = hover } }
}

struct PillPicker: View {
    @Binding var selection: Int; let lang: AppLanguage; let queueCount: Int; @Namespace private var animation
    var body: some View { HStack(spacing: 0) { pillButton(title: tr("Editor & Import", lang: lang), tag: 0); pillButton(title: "\(tr("Process Queue", lang: lang)) (\(queueCount))", tag: 1) }.padding(4).background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)).frame(width: 280) }
    @ViewBuilder private func pillButton(title: String, tag: Int) -> some View { Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = tag } } label: { Text(title).font(.system(size: 13, weight: selection == tag ? .medium : .regular)).foregroundStyle(selection == tag ? .primary : .secondary).frame(maxWidth: .infinity).padding(.vertical, 6).background { if selection == tag { Capsule().fill(Color(NSColor.controlColor)).shadow(color: .black.opacity(0.1), radius: 2, y: 1).matchedGeometryEffect(id: "ACTIVETAB", in: animation) } }.contentShape(Capsule()) }.buttonStyle(.plain) }
}

struct EditorDetailView: View {
    @Environment(AppState.self) private var appState; @Binding var selectedVideoIDs: Set<UUID>; @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue; var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    @State private var nfoTemplate = NFOData(); @State private var currentGenreInput: String = ""; @State private var isOCRExtracting: Bool = false; let addQueueNotifier = NotificationCenter.default.publisher(for: .init("TriggerAddToQueue"))
    let years = Array(1900...Calendar.current.component(.year, from: Date()) + 5).reversed(); let presetCountries = ["China", "Hongkong", "Taiwan", "US", "Japan", "Korean", "UK", "France", "Germany"]
    private var selectedVideos: [VideoItem] { appState.importedVideos.filter { selectedVideoIDs.contains($0.id) } }
    
    // Core Mod 4: Deep track OCR status
    @State private var ocrPhase = 0

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView { formContent.padding().padding(.top, 178) }
            
            // Header rendered naturally in ZStack, without clipping anomalies
            EditorHeaderView(
                selectedVideos: selectedVideos,
                cache: appState.thumbnailsCache,
                durationsCache: appState.durationsCache,
                lang: lang,
                targetFilename: $nfoTemplate.targetFilename
            )
        }
        .onReceive(addQueueNotifier) { _ in submitToQueue() }
        .onChange(of: selectedVideoIDs) { oldSelection, newSelection in
            ocrPhase = 0 // Reset depth search on video change
            handleSelectionChange(newSelection)
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label(tr("Basic Info", lang: lang), systemImage: "info.circle").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledTextField(label: tr("Title", lang: lang), text: $nfoTemplate.title)
                    HStack(spacing: 12) { Text(tr("Year", lang: lang)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); Picker("", selection: $nfoTemplate.year) { Text(tr("Leave Empty", lang: lang)).tag(""); ForEach(years, id: \.self) { year in Text(String(year)).tag(String(year)) } }.pickerStyle(.menu).frame(width: 100); Text(tr("Country", lang: lang)).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing); Picker("", selection: $nfoTemplate.country) { Text(tr("Leave Empty", lang: lang)).tag(""); ForEach(presetCountries, id: \.self) { c in Text(c).tag(c) } }.pickerStyle(.menu).frame(width: 110); Spacer() }
                    HStack(spacing: 12) { Text(tr("Premiered", lang: lang)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); Toggle("", isOn: $nfoTemplate.enablePremiered).labelsHidden(); if nfoTemplate.enablePremiered { DatePicker("", selection: $nfoTemplate.premieredDate, displayedComponents: .date).labelsHidden().onChange(of: nfoTemplate.premieredDate) { oldDate, newDate in nfoTemplate.year = String(Calendar.current.component(.year, from: newDate)) } } else { Text(tr("Not Selected", lang: lang)).font(.caption).foregroundStyle(.tertiary) }; Spacer() }
                    DirectorField(director: $nfoTemplate.director, lang: lang); LabeledTextField(label: tr("Studio", lang: lang), text: $nfoTemplate.studio); GenreField(genres: $nfoTemplate.genres, currentInput: $currentGenreInput, lang: lang)
                }.padding(.top, 8)
            }
            GroupBox(label: Label("\(tr("Rating", lang: lang)): \(String(format: "%.1f", nfoTemplate.rating))", systemImage: "star.circle").font(.headline)) { HStack(spacing: 12) { Slider(value: $nfoTemplate.rating, in: 0...10, step: 0.1); if nfoTemplate.rating > 0 { Button(tr("Clear Rating", lang: lang)) { nfoTemplate.rating = 0 }.buttonStyle(.borderless).foregroundStyle(.secondary) } }.padding(.top, 8) }
            
            GroupBox(label: HStack {
                Label(tr("Plot", lang: lang), systemImage: "text.alignleft").font(.headline); Spacer()
                Button(action: {
                    guard let video = selectedVideos.first else { return }; isOCRExtracting = true
                    let targetTime: Double
                    if ocrPhase == 0 { targetTime = 0.0 }
                    else if ocrPhase == 1 { targetTime = 5.0 }
                    else { targetTime = 5.0 + Double(ocrPhase - 1) * 10.0 }
                    
                    Task {
                        let text = await appState.performOCR(on: video.fileURL, times: [targetTime])
                        await MainActor.run {
                            if !text.isEmpty { nfoTemplate.plot += (nfoTemplate.plot.isEmpty ? "" : "\n") + text }
                            isOCRExtracting = false
                            ocrPhase += 1
                        }
                    }
                }) {
                    if isOCRExtracting { ProgressView().controlSize(.small) }
                    else { Label(ocrPhase == 0 ? tr("OCR", lang: lang) : tr("Extract More", lang: lang), systemImage: "text.viewfinder") }
                }.buttonStyle(.glass).controlSize(.small).disabled(isOCRExtracting || selectedVideos.isEmpty)
            }) { TextEditor(text: $nfoTemplate.plot).frame(minHeight: 90, maxHeight: 160).font(.body).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1)).padding(.top, 8) }
            
            GroupBox(label: Label(tr("Actors", lang: lang), systemImage: "person.2").font(.headline)) { VStack(spacing: 8) { ForEach($nfoTemplate.actors) { $actor in ActorRow(actor: $actor, lang: lang) { nfoTemplate.actors.removeAll { $0.id == actor.id } } }; Button { nfoTemplate.actors.append(Actor()) } label: { Label(tr("Add Actor", lang: lang), systemImage: "person.badge.plus") }.buttonStyle(.borderless).padding(.top, 4) }.padding(.top, 8) }
            GallerySection(nfoData: $nfoTemplate, videoURL: selectedVideos.first?.fileURL, lang: lang)
            HStack { Spacer(); if #available(macOS 15.0, *) { Button { submitToQueue() } label: { Label(tr("Add to Queue", lang: lang), systemImage: "arrow.right.square.fill") }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).disabled(selectedVideoIDs.isEmpty).keyboardShortcut(.return, modifiers: [.command]) } else { Button { submitToQueue() } label: { Label(tr("Add to Queue", lang: lang), systemImage: "arrow.right.square.fill").padding(.horizontal, 24).padding(.vertical, 8) }.buttonStyle(.borderedProminent).clipShape(Capsule()).disabled(selectedVideoIDs.isEmpty).keyboardShortcut(.return, modifiers: [.command]) } }
        }
    }

    private func submitToQueue() { appState.addToQueue(videos: selectedVideos, data: nfoTemplate) }
    private func extractDateFromFileName(_ name: String) -> Date? { guard let regex = try? NSRegularExpression(pattern: "(19|20)\\d{2}[-.]?(0[1-9]|1[0-2])[-.]?(0[1-9]|[12][0-9]|3[01])") else { return nil }; let nsString = name as NSString; let results = regex.matches(in: name, range: NSRange(location: 0, length: nsString.length)); if let match = results.first { var dateStr = nsString.substring(with: match.range); dateStr = dateStr.replacingOccurrences(of: ".", with: "-"); let formatter = DateFormatter(); formatter.dateFormat = dateStr.count == 8 ? "yyyyMMdd" : "yyyy-MM-dd"; return formatter.date(from: dateStr) }; return nil }
    private func handleSelectionChange(_ newSelection: Set<UUID>) {
        Task { for id in newSelection { if let video = appState.importedVideos.first(where: { $0.id == id }) { await appState.loadMetadata(for: video.fileURL) } } }; let validVideos = appState.importedVideos.filter { newSelection.contains($0.id) }
        if validVideos.count == 1, let video = validVideos.first { nfoTemplate = NFOData(); nfoTemplate.targetFilename = video.baseName; if let extractedDate = extractDateFromFileName(video.baseName) { nfoTemplate.enablePremiered = true; nfoTemplate.premieredDate = extractedDate; nfoTemplate.year = String(Calendar.current.component(.year, from: extractedDate)) }; if let parsedNFO = parseExistingNFO(for: video) { mergeSingleNFO(parsedNFO) } } else if validVideos.count > 1 { nfoTemplate = NFOData(); let parsedNFOs = validVideos.compactMap { parseExistingNFO(for: $0) }; if let firstNFO = parsedNFOs.first, parsedNFOs.count == validVideos.count { var common = firstNFO; for nfo in parsedNFOs.dropFirst() { if common.year != nfo.year { common.year = "" }; if common.country != nfo.country { common.country = "" }; if common.studio != nfo.studio { common.studio = "" }; if common.director != nfo.director { common.director = "" }; common.genres = common.genres.filter { nfo.genres.contains($0) }; common.actors = common.actors.filter { a1 in nfo.actors.contains(where: { $0.name == a1.name }) } }; common.title = ""; common.plot = ""; common.rating = 0.0; common.targetFilename = ""; common.enablePremiered = false; common.posterURL = nil; common.fanartURLs = []; nfoTemplate = common } } else { nfoTemplate = NFOData() }
    }
    private func parseExistingNFO(for video: VideoItem) -> NFOData? {
        let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo"); guard FileManager.default.fileExists(atPath: nfoURL.path), let xmlDoc = try? XMLDocument(contentsOf: nfoURL, options: []), let root = xmlDoc.rootElement() else { return nil }; var nfo = NFOData(); nfo.title = root.elements(forName: "title").first?.stringValue ?? ""; nfo.year = root.elements(forName: "year").first?.stringValue ?? ""; nfo.country = root.elements(forName: "country").first?.stringValue ?? ""; nfo.studio = root.elements(forName: "studio").first?.stringValue ?? ""; if let pStr = root.elements(forName: "premiered").first?.stringValue { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; if let pDate = df.date(from: pStr) { nfo.enablePremiered = true; nfo.premieredDate = pDate } }; nfo.director = root.elements(forName: "director").first?.stringValue ?? ""; nfo.plot = root.elements(forName: "plot").first?.stringValue ?? ""; if let r = Double(root.elements(forName: "userrating").first?.stringValue ?? "") { nfo.rating = r }; nfo.genres = root.elements(forName: "genre").compactMap { $0.stringValue }; nfo.actors = root.elements(forName: "actor").compactMap { node in let name = node.elements(forName: "name").first?.stringValue ?? ""; guard !name.isEmpty else { return nil }; return Actor(name: name, role: node.elements(forName: "role").first?.stringValue ?? "") }; return nfo
    }
    private func mergeSingleNFO(_ nfo: NFOData) { if !nfo.title.isEmpty { nfoTemplate.title = nfo.title }; if !nfo.year.isEmpty { nfoTemplate.year = nfo.year }; if !nfo.country.isEmpty { nfoTemplate.country = nfo.country }; if !nfo.studio.isEmpty { nfoTemplate.studio = nfo.studio }; if nfo.enablePremiered { nfoTemplate.enablePremiered = true; nfoTemplate.premieredDate = nfo.premieredDate }; if !nfo.director.isEmpty { nfoTemplate.director = nfo.director }; if !nfo.plot.isEmpty { nfoTemplate.plot = nfo.plot }; if nfo.rating > 0 { nfoTemplate.rating = nfo.rating }; if !nfo.genres.isEmpty { nfoTemplate.genres = nfo.genres }; if !nfo.actors.isEmpty { nfoTemplate.actors = nfo.actors } }
}

struct QueueView: View {
    @Environment(AppState.self) private var appState; @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue; var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    var body: some View {
        VStack(spacing: 0) {
            Table(appState.queue) {
                TableColumn(tr("Target Video", lang: lang)) { item in Text(item.video.fileName).lineLimit(1).truncationMode(.middle) }; TableColumn(tr("Write Title", lang: lang)) { item in Text(item.nfoData.title.isEmpty ? tr("Auto Detect", lang: lang) : item.nfoData.title).lineLimit(1).foregroundStyle(item.nfoData.title.isEmpty ? .secondary : .primary) }
                TableColumn(tr("Status", lang: lang)) { item in VStack(alignment: .leading, spacing: 2) { Text(statusLabel(item.status, lang: lang)).foregroundStyle(statusColor(item.status)).fontWeight(.medium); if item.status == .error && !item.errorMessage.isEmpty { Text(item.errorMessage).font(.caption2).foregroundStyle(.red) } } }
                TableColumn(tr("Actions", lang: lang)) { item in Button { appState.queue.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red).disabled(item.status == .processing) }.width(60)
            }.contextMenu(forSelectionType: QueueItem.ID.self) { items in Button(tr("Reveal in Finder", lang: lang)) { let urls = appState.queue.filter { items.contains($0.id) }.map { $0.video.fileURL }; if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) } }; Divider(); Button(tr("Remove Selected Tasks", lang: lang), role: .destructive) { appState.queue.removeAll { items.contains($0.id) } } }
            Divider()
            HStack {
                Button(tr("Clear Done", lang: lang)) { appState.queue.removeAll { $0.status == .success } }.disabled(appState.queue.allSatisfy { $0.status != .success }); Spacer()
                let waiting = appState.queue.filter { $0.status == .waiting }.count; let done = appState.queue.filter { $0.status == .success }.count
                if !appState.queue.isEmpty { Text("\(tr("Waiting", lang: lang)) \(waiting) · \(tr("Done", lang: lang)) \(done)").font(.caption).foregroundStyle(.secondary) }
                if #available(macOS 15.0, *) { Button { appState.processQueue() } label: { Label(tr("Generate NFO", lang: lang), systemImage: "play.fill") }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.green).disabled(appState.queue.filter { $0.status == .waiting }.isEmpty).keyboardShortcut(.return, modifiers: [.command, .shift]) } else { Button { appState.processQueue() } label: { Label(tr("Generate NFO", lang: lang), systemImage: "play.fill").padding(.horizontal, 28).padding(.vertical, 8) }.buttonStyle(.borderedProminent).clipShape(Capsule()).tint(.green).disabled(appState.queue.filter { $0.status == .waiting }.isEmpty).keyboardShortcut(.return, modifiers: [.command, .shift]) }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }
    private func statusLabel(_ status: QueueItem.QueueStatus, lang: AppLanguage) -> String { switch status { case .waiting: return tr("status.waiting", lang: lang); case .processing: return tr("status.processing", lang: lang); case .success: return tr("status.success", lang: lang); case .error: return tr("status.error", lang: lang) } }
    private func statusColor(_ status: QueueItem.QueueStatus) -> Color { switch status { case .success: return .green; case .error: return .red; case .processing: return .orange; case .waiting: return .secondary } }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState; @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue; var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all; @State private var selectedVideoIDs = Set<UUID>(); @State private var viewMode: Int = 0; @State private var isImportingVideos = false
    let importNotifier = NotificationCenter.default.publisher(for: .init("TriggerImportVideos"))
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) { SidebarView(selectedVideoIDs: $selectedVideoIDs, isImportingVideos: $isImportingVideos) } detail: { ZStack(alignment: .top) { if viewMode == 0 { EditorDetailView(selectedVideoIDs: $selectedVideoIDs) } else { QueueView().padding(.top, 64) }; PillPicker(selection: $viewMode, lang: lang, queueCount: appState.queue.count).padding(.top, 14).zIndex(100) }.ignoresSafeArea(.all, edges: .top) }.navigationSplitViewStyle(.balanced).onReceive(importNotifier) { _ in isImportingVideos = true }.frame(minWidth: 1080, minHeight: 720).id(languageRaw)
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState; @Binding var selectedVideoIDs: Set<UUID>; @Binding var isImportingVideos: Bool; @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue; var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }; @State private var previewURL: URL?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                List(selection: $selectedVideoIDs) { ForEach(appState.importedVideos) { video in Text(video.fileName).lineLimit(2).truncationMode(.middle).tag(video.id).scaleEffect(previewURL == video.fileURL ? 1.05 : 1.0).opacity(previewURL == video.fileURL ? 0.8 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.6), value: previewURL) }.onDelete { indices in let idsToDelete = indices.map { appState.importedVideos[$0].id }; appState.importedVideos.remove(atOffsets: indices); idsToDelete.forEach { selectedVideoIDs.remove($0) } }; Color.clear.frame(maxWidth: .infinity, minHeight: 600).listRowBackground(Color.clear).contentShape(Rectangle()).onTapGesture { selectedVideoIDs.removeAll() } }.contextMenu(forSelectionType: VideoItem.ID.self) { items in if !items.isEmpty { Button(tr("Reveal in Finder", lang: lang)) { let urls = appState.importedVideos.filter { items.contains($0.id) }.map { $0.fileURL }; if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) } }; Divider(); Button(tr("Remove from List", lang: lang), role: .destructive) { withAnimation { appState.importedVideos.removeAll { items.contains($0.id) }; items.forEach { selectedVideoIDs.remove($0) } } } } }.quickLookPreview($previewURL)
                Button("") { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { if selectedVideoIDs.count == 1, let id = selectedVideoIDs.first, let video = appState.importedVideos.first(where: { $0.id == id }) { previewURL = video.fileURL } } }.keyboardShortcut(.space, modifiers: []).opacity(0)
                if appState.importedVideos.isEmpty { VStack(spacing: 8) { Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.tertiary); Text(tr("Drop Videos Here", lang: lang)).font(.caption).foregroundStyle(.tertiary) } }
            }.background(Color.clear.contentShape(Rectangle()).onTapGesture { selectedVideoIDs.removeAll() })
            Divider()
            HStack(spacing: 0) { Button { isImportingVideos = true } label: { Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(tr("Import", lang: lang)); Button { withAnimation { appState.importedVideos.removeAll { selectedVideoIDs.contains($0.id) }; selectedVideoIDs.removeAll() } } label: { Image(systemName: "minus").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(tr("Remove Selected", lang: lang)).disabled(selectedVideoIDs.isEmpty); Button { withAnimation { appState.toggleSort() } } label: { Image(systemName: appState.sortOption == .added ? "textformat.abc" : "clock").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(appState.sortOption == .added ? tr("Sort by Name", lang: lang) : tr("Sort by Added", lang: lang)); Spacer(); if !selectedVideoIDs.isEmpty { Text("\(tr("Selected Count", lang: lang)) \(selectedVideoIDs.count)").font(.caption).foregroundStyle(.secondary).padding(.trailing, 8) } }.padding(.horizontal, 8).frame(height: 36).background(.bar)
        }.navigationTitle(tr("Import Videos", lang: lang)).frame(minWidth: 220, idealWidth: 260)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in let collector = DropCollector(); let group = DispatchGroup(); for provider in providers { group.enter(); _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url = url { Task { await collector.add(url); group.leave() } } else { group.leave() } } }; group.notify(queue: .main) { Task { let finalURLs = await collector.urls; appState.importFiles(urls: finalURLs) } }; return true }
        .fileImporter(isPresented: $isImportingVideos, allowedContentTypes: [.audiovisualContent], allowsMultipleSelection: true) { result in if case .success(let urls) = result { appState.importFiles(urls: urls) } }
    }
}

// MARK: - Setting Views
struct SettingsView: View {
    @AppStorage("appTheme")    private var appThemeRaw: String = AppTheme.system.rawValue; @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.zhHans.rawValue
    var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .zhHans }
    private var appThemeBinding: Binding<AppTheme> { Binding(get: { AppTheme(rawValue: appThemeRaw) ?? .system }, set: { appThemeRaw = $0.rawValue }) }
    private var languageBinding: Binding<String> { Binding(get: { languageRaw }, set: { newValue in languageRaw = newValue; if let newLang = AppLanguage(rawValue: newValue) { applyGlobalLanguage(newLang) } }) }
    var body: some View { Form { Section { Picker(tr("Theme Setting", lang: lang), selection: appThemeBinding) { ForEach(AppTheme.allCases, id: \.rawValue) { theme in Text(theme.rawValue).tag(theme as AppTheme) } }; Picker(tr("App Language", lang: lang), selection: languageBinding) { ForEach(AppLanguage.allCases, id: \.rawValue) { l in Text(l.rawValue).tag(l.rawValue) } }; Text(tr("Language Restart Hint", lang: lang)).font(.caption).foregroundStyle(.tertiary) } header: { Text(tr("Appearance & Lang", lang: lang)).font(.headline) }; Section { Text(tr("Cache Hint", lang: lang)).font(.caption).foregroundStyle(.secondary); HStack(spacing: 12) { Button(tr("Clear Directors", lang: lang)) { CacheManager.shared.clear(category: "director") }; Button(tr("Clear Genres", lang: lang)) { CacheManager.shared.clear(category: "genre") }; Button(tr("Clear Actors", lang: lang)) { CacheManager.shared.clear(category: "actor") } }; Button(tr("Clear All", lang: lang), role: .destructive) { CacheManager.shared.clear() } } header: { Text(tr("Cache Management", lang: lang)).font(.headline) } }.formStyle(.grouped).padding().frame(width: 480, height: 360) }
}
