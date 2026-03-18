import SwiftUI
import UIKit
import Combine

final class RichTextEditorCommands: ObservableObject {
    fileprivate weak var textView: UITextView?

    func toggleBold() {
        guard let textView else { return }
        RichTextEditorFormatting.toggleBold(in: textView)
    }

    func toggleUnderline() {
        guard let textView else { return }
        RichTextEditorFormatting.toggleUnderline(in: textView)
    }

    func increaseTextSize() {
        guard let textView else { return }
        RichTextEditorFormatting.increaseTextSize(in: textView)
    }

    func decreaseTextSize() {
        guard let textView else { return }
        RichTextEditorFormatting.decreaseTextSize(in: textView)
    }

    func indent() {
        guard let textView else { return }
        RichTextEditorFormatting.indent(in: textView)
    }

    func outdent() {
        guard let textView else { return }
        RichTextEditorFormatting.outdent(in: textView)
    }

    func toggleBullets() {
        guard let textView else { return }
        RichTextEditorFormatting.toggleBullets(in: textView)
    }
}

struct RichTextEditor: UIViewRepresentable {
    fileprivate enum Storage {
        case plain(Binding<String>)
        case attributed(Binding<NSAttributedString>)
    }

    private let storage: Storage
    var commands: RichTextEditorCommands?
    var isEditable: Bool
    var font: UIFont
    var textColor: UIColor
    var backgroundColor: UIColor

    init(
        text: Binding<String>,
        isEditable: Bool = true,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        backgroundColor: UIColor = .clear,
        commands: RichTextEditorCommands? = nil
    ) {
        self.storage = .plain(text)
        self.commands = commands
        self.isEditable = isEditable
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    init(
        attributedText: Binding<NSAttributedString>,
        isEditable: Bool = true,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        backgroundColor: UIColor = .clear,
        commands: RichTextEditorCommands? = nil
    ) {
        self.storage = .attributed(attributedText)
        self.commands = commands
        self.isEditable = isEditable
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(storage: storage)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        configure(textView)
        applyCurrentValue(to: textView, preserveSelection: false)
        commands?.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        configure(uiView)
        applyCurrentValue(to: uiView, preserveSelection: true)
        commands?.textView = uiView
    }

    private func configure(_ textView: UITextView) {
        textView.isEditable = isEditable
        textView.isScrollEnabled = true
        textView.backgroundColor = backgroundColor
        textView.textColor = textColor
        textView.font = font
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
    }

    private func currentAttributedValue() -> NSAttributedString {
        switch storage {
        case .plain(let binding):
            return NSAttributedString(
                string: binding.wrappedValue,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor
                ]
            )
        case .attributed(let binding):
            return normalizedAttributedString(binding.wrappedValue)
        }
    }

    private func normalizedAttributedString(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)

        guard fullRange.length > 0 else {
            return mutable
        }

        // Display all text at the editor's configured size for readability,
        // while preserving traits like bold and italic.
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let baseFont = (value as? UIFont) ?? font
            let descriptor = baseFont.fontDescriptor
            let displayFont = UIFont(descriptor: descriptor, size: font.pointSize)
            mutable.addAttribute(.font, value: displayFont, range: range)
        }

        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)

        return mutable
    }

    private func applyCurrentValue(to textView: UITextView, preserveSelection: Bool) {
        let currentValue = currentAttributedValue()

        if textView.attributedText != currentValue {
            let selectedRange = textView.selectedRange
            textView.attributedText = currentValue
            if preserveSelection, selectedRange.location <= textView.attributedText.length {
                textView.selectedRange = selectedRange
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let storage: Storage

        fileprivate init(storage: Storage) {
            self.storage = storage
        }

        func textViewDidChange(_ textView: UITextView) {
            switch storage {
            case .plain(let binding):
                binding.wrappedValue = textView.text
            case .attributed(let binding):
                binding.wrappedValue = textView.attributedText ?? NSAttributedString(string: "")
            }
        }
    }
}

extension NSAttributedString {
    static func eyeBrary_fromRTFData(_ data: Data) throws -> NSAttributedString {
        try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    func eyeBrary_toRTFData() throws -> Data {
        try data(
            from: NSRange(location: 0, length: length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

private enum RichTextEditorFormatting {
    static func toggleBold(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let currentFont = (value as? UIFont) ?? (textView.typingAttributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
                let descriptor = currentFont.fontDescriptor
                let traits = descriptor.symbolicTraits
                let newTraits: UIFontDescriptor.SymbolicTraits = traits.contains(.traitBold)
                    ? traits.subtracting(.traitBold)
                    : traits.union(.traitBold)
                let newDescriptor = descriptor.withSymbolicTraits(newTraits) ?? descriptor
                let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
                mutable.addAttribute(.font, value: newFont, range: subrange)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            textView.delegate?.textViewDidChange?(textView)
        } else {
            let currentFont = (textView.typingAttributes[.font] as? UIFont) ?? textView.font ?? .preferredFont(forTextStyle: .body)
            let descriptor = currentFont.fontDescriptor
            let traits = descriptor.symbolicTraits
            let newTraits: UIFontDescriptor.SymbolicTraits = traits.contains(.traitBold)
                ? traits.subtracting(.traitBold)
                : traits.union(.traitBold)
            let newDescriptor = descriptor.withSymbolicTraits(newTraits) ?? descriptor
            let newFont = UIFont(descriptor: newDescriptor, size: currentFont.pointSize)
            textView.typingAttributes[.font] = newFont
        }
    }

    static func toggleUnderline(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttribute(.underlineStyle, in: range, options: []) { value, subrange, _ in
                let current = (value as? Int) ?? 0
                let next = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                mutable.addAttribute(.underlineStyle, value: next, range: subrange)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            textView.delegate?.textViewDidChange?(textView)
        } else {
            let current = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
            textView.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        }
    }

    static func increaseTextSize(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let currentFont = (value as? UIFont) ?? (textView.typingAttributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
                let descriptor = currentFont.fontDescriptor
                let newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize + 2)
                mutable.addAttribute(.font, value: newFont, range: subrange)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            textView.delegate?.textViewDidChange?(textView)
        } else {
            let currentFont = (textView.typingAttributes[.font] as? UIFont) ?? textView.font ?? .preferredFont(forTextStyle: .body)
            let descriptor = currentFont.fontDescriptor
            let newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize + 2)
            textView.typingAttributes[.font] = newFont
        }
    }

    static func decreaseTextSize(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let currentFont = (value as? UIFont) ?? (textView.typingAttributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
                let descriptor = currentFont.fontDescriptor
                let newSize = max(10, currentFont.pointSize - 2)
                let newFont = UIFont(descriptor: descriptor, size: newSize)
                mutable.addAttribute(.font, value: newFont, range: subrange)
            }
            textView.attributedText = mutable
            textView.selectedRange = range
            textView.delegate?.textViewDidChange?(textView)
        } else {
            let currentFont = (textView.typingAttributes[.font] as? UIFont) ?? textView.font ?? .preferredFont(forTextStyle: .body)
            let descriptor = currentFont.fontDescriptor
            let newSize = max(10, currentFont.pointSize - 2)
            let newFont = UIFont(descriptor: descriptor, size: newSize)
            textView.typingAttributes[.font] = newFont
        }
    }

    static func indent(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        let paragraphRange = (textView.text as NSString).paragraphRange(for: range)
        mutable.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent += 16
            style.headIndent += 16
            mutable.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        textView.attributedText = mutable
        textView.selectedRange = range
        textView.delegate?.textViewDidChange?(textView)
    }

    static func outdent(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        let paragraphRange = (textView.text as NSString).paragraphRange(for: range)
        mutable.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, subrange, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = max(0, style.firstLineHeadIndent - 16)
            style.headIndent = max(0, style.headIndent - 16)
            mutable.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        textView.attributedText = mutable
        textView.selectedRange = range
        textView.delegate?.textViewDidChange?(textView)
    }

    static func toggleBullets(in textView: UITextView) {
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }

        let nsText = textView.text as NSString
        let paragraphRange = nsText.paragraphRange(for: range)
        let paragraphText = nsText.substring(with: paragraphRange)
        let lines = paragraphText.components(separatedBy: .newlines)

        let shouldRemoveBullets = lines
            .filter { !$0.isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("• ") }

        let updatedLines = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if shouldRemoveBullets {
                return line.replacingOccurrences(of: "^\\s*•\\s", with: "", options: .regularExpression)
            } else {
                return "• " + line
            }
        }

        let replacement = updatedLines.joined(separator: "\n")
        let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
        let replacementAttributed = NSMutableAttributedString(string: replacement, attributes: textView.typingAttributes)

        let fullReplacementRange = NSRange(location: 0, length: replacementAttributed.length)
        let bulletFont = (textView.typingAttributes[.font] as? UIFont) ?? textView.font ?? .preferredFont(forTextStyle: .body)
        let bulletIndent = ceil(("• " as NSString).size(withAttributes: [.font: bulletFont]).width)

        replacementAttributed.enumerateAttribute(.paragraphStyle, in: fullReplacementRange, options: []) { value, subrange, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            if shouldRemoveBullets {
                style.firstLineHeadIndent = 0
                style.headIndent = 0
            } else {
                style.firstLineHeadIndent = 0
                style.headIndent = bulletIndent
            }
            replacementAttributed.addAttribute(.paragraphStyle, value: style, range: subrange)
        }

        mutable.replaceCharacters(in: paragraphRange, with: replacementAttributed)
        textView.attributedText = mutable
        let newLength = (replacement as NSString).length
        textView.selectedRange = NSRange(location: paragraphRange.location, length: min(newLength, mutable.length - paragraphRange.location))
        textView.delegate?.textViewDidChange?(textView)
    }
}
