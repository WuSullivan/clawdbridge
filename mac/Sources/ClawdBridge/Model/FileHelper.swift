import Foundation
import UniformTypeIdentifiers

/// 文件工具：MIME 类型和 UTI 映射
/// 用于剪贴板读写时保持富文件元数据
enum FileHelper {
    /// 从文件扩展名推导 UTType
    static func uttype(for ext: String) -> UTType? {
        UTType(filenameExtension: ext.lowercased())
    }

    /// 常用文档类型的 UTI
    static let docTypes: Set<String> = [
        "org.openxmlformats.wordprocessingml.document",  // .docx
        "com.microsoft.word.doc",                        // .doc
        "org.openxmlformats.presentationml.presentation",// .pptx
        "com.microsoft.powerpoint.ppt",                  // .ppt
        "org.openxmlformats.spreadsheetml.sheet",        // .xlsx
        "com.microsoft.excel.xls",                       // .xls
        "com.adobe.pdf",                                 // .pdf
        "com.apple.iwork.pages.pages",                   // .pages
        "com.apple.iwork.numbers.numbers",               // .numbers
        "com.apple.iwork.keynote.key",                   // .key
        "org.oasis.opendocument.text",                   // .odt
        "org.oasis.opendocument.spreadsheet",            // .ods
        "org.oasis.opendocument.presentation",            // .odp
        "public.rtf",                                    // .rtf
        "public.comma-separated-values-text",            // .csv
        "public.plain-text",                             // .txt, .md
    ]

    /// 判断是否为文档类型
    static func isDocumentType(_ type: UTType?) -> Bool {
        guard let type = type else { return false }
        return docTypes.contains(type.identifier) || docTypes.contains(where: {
            type.conforms(to: UTType($0) ?? .data)
        })
    }

    /// 文件扩展名映射表
    static let extensionMap: [String: String] = [
        "doc": "com.microsoft.word.doc",
        "docx": "org.openxmlformats.wordprocessingml.document",
        "ppt": "com.microsoft.powerpoint.ppt",
        "pptx": "org.openxmlformats.presentationml.presentation",
        "xls": "com.microsoft.excel.xls",
        "xlsx": "org.openxmlformats.spreadsheetml.sheet",
        "pdf": "com.adobe.pdf",
        "pages": "com.apple.iwork.pages.pages",
        "numbers": "com.apple.iwork.numbers.numbers",
        "key": "com.apple.iwork.keynote.key",
        "odt": "org.oasis.opendocument.text",
        "ods": "org.oasis.opendocument.spreadsheet",
        "odp": "org.oasis.opendocument.presentation",
        "rtf": "public.rtf",
        "csv": "public.comma-separated-values-text",
        "txt": "public.plain-text",
        "md": "public.plain-text",
        "png": "public.png",
        "jpg": "public.jpeg",
        "jpeg": "public.jpeg",
        "gif": "com.compuserve.gif",
        "heic": "public.heic",
        "webp": "org.webmproject.webp",
        "bmp": "com.microsoft.bmp",
        "tiff": "public.tiff",
        "mp4": "public.mpeg-4",
        "mov": "com.apple.quicktime-movie",
        "m4v": "com.apple.m4v-video",
        "avi": "public.avi",
        "mkv": "org.matroska.mkv",
        "webm": "org.webmproject.webm",
    ]
}
