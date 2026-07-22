import Foundation
import UIKit
import PDFKit
import CoreText

//  PlanPDFBuilder.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//

// MARK: - PDF builder

enum PlanPDFBuilder {
    static func buildPDF(
        patientName: String,
        reportTitle: String,
        reportDate: Date,
        entries: [PlanEntry],
        letterheadURL: URL?,
        safeZoneConfig: SafeZoneConfig?,
        bodyFontSize: CGFloat = 10
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary-Report.pdf")
        let numberedOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary-Report-Numbered.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let W = pageRect.width, H = pageRect.height
        let contentStartY:  CGFloat
        let contentBottomY: CGFloat
        let contentLeftX:   CGFloat
        let contentRightX:  CGFloat
        if let z = safeZoneConfig?.safeZone {
            contentStartY  = z.minY * H
            contentBottomY = z.maxY * H
            contentLeftX   = z.minX * W
            contentRightX  = z.maxX * W
        } else {
            contentStartY  = 112
            contentBottomY = H - 120
            contentLeftX   = 54
            contentRightX  = W - 54
        }
        let contentWidth = contentRightX - contentLeftX
        let continuationReserve: CGFloat = 10

        try renderer.writePDF(to: outputURL) { context in
            let headingFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let subheadingFont = UIFont.systemFont(ofSize: max(12, bodyFontSize + 2), weight: .semibold)
            let entryHeaderFont = UIFont.systemFont(ofSize: max(12, bodyFontSize + 2), weight: .bold)
            let bodyFont = UIFont.systemFont(ofSize: bodyFontSize)
            let continuationFont = UIFont.italicSystemFont(ofSize: 9)
            let bodyLineHeight = ceil(bodyFont.lineHeight)

            var y: CGFloat = contentStartY

            func drawLetterhead(on context: UIGraphicsPDFRendererContext) {
                if let letterheadURL,
                   let pdfDoc = PDFDocument(url: letterheadURL),
                   let page = pdfDoc.page(at: 0) {
                    let cg = context.cgContext
                    cg.saveGState()

                    // PDFPage.draw uses PDF-style coordinates, while this renderer context
                    // is UIKit-style. Flip once before drawing the imported page so the
                    // letterhead appears upright and not mirrored.
                    cg.translateBy(x: 0, y: pageRect.height)
                    cg.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: cg)

                    cg.restoreGState()
                }
            }

            func drawContinuationNote() {
                let note = "Continued on next page"
                let noteRect = CGRect(x: contentLeftX + 18, y: contentBottomY - continuationReserve, width: contentWidth - 18, height: 12)
                (note as NSString).draw(in: noteRect, withAttributes: [
                    .font: continuationFont,
                    .foregroundColor: UIColor.darkGray
                ])
            }

            func continueOnNextPage() {
                drawContinuationNote()
                context.beginPage()
                drawLetterhead(on: context)
                y = contentStartY
            }

            // MARK: Splitting (TextKit line boundaries — a break can never land mid-word)

            /// Character count that fits within `maxHeight` at `width`, measured by
            /// laying the string into a real text container so the cut always lands
            /// on a line-fragment boundary.
            func lineBreakFitLength(for attributedString: NSAttributedString, width: CGFloat, maxHeight: CGFloat) -> Int {
                guard attributedString.length > 0, maxHeight > 0 else { return 0 }
                let storage = NSTextStorage(attributedString: attributedString)
                let layout = NSLayoutManager()
                storage.addLayoutManager(layout)
                let container = NSTextContainer(size: CGSize(width: width, height: maxHeight))
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let glyphRange = layout.glyphRange(for: container)
                return layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).length
            }

            /// Length of just the first laid-out line — the overflow guard when not
            /// even one line fits on an otherwise empty page.
            func firstLineLength(of attributedString: NSAttributedString, width: CGFloat) -> Int {
                guard attributedString.length > 0 else { return 0 }
                let storage = NSTextStorage(attributedString: attributedString)
                let layout = NSLayoutManager()
                storage.addLayoutManager(layout)
                let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
                container.lineFragmentPadding = 0
                container.maximumNumberOfLines = 1
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let glyphRange = layout.glyphRange(for: container)
                return layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).length
            }

            /// Widow/orphan check on the PARAGRAPH the cut lands in (not the whole
            /// chunk): the fragment kept on this page must be at least
            /// `minimumLinesAtBottom` lines and the fragment carried to the next page
            /// at least `minimumLinesAtTop`.
            func splitLeavesCleanFragments(
                _ attributedString: NSAttributedString,
                splitIndex: Int,
                width: CGFloat,
                minimumLinesAtBottom: Int,
                minimumLinesAtTop: Int
            ) -> Bool {
                let text = attributedString.string as NSString
                let paragraph = text.paragraphRange(for: NSRange(location: splitIndex, length: 0))

                func fragmentHeight(_ range: NSRange) -> CGFloat {
                    guard range.length > 0 else { return 0 }
                    let rect = attributedString.attributedSubstring(from: range).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    return ceil(rect.height)
                }

                let headFragment = NSRange(location: paragraph.location, length: splitIndex - paragraph.location)
                let tailFragment = NSRange(location: splitIndex, length: NSMaxRange(paragraph) - splitIndex)
                return fragmentHeight(headFragment) >= CGFloat(minimumLinesAtBottom) * bodyLineHeight
                    && fragmentHeight(tailFragment) >= CGFloat(minimumLinesAtTop) * bodyLineHeight
            }

            /// Where to cut `attributedString` for this page. Preference order:
            /// 1. the line-boundary fit when it already lands at a paragraph break;
            /// 2. the line-boundary fit when the cut paragraph keeps >=3 of its lines
            ///    here and sends >=2 to the next page (no widows/orphans);
            /// 3. the last paragraph break that fits (the cut paragraph moves whole);
            /// 4. the line-boundary fit regardless (the paragraph started this page
            ///    and is too tall for it — it has to split somewhere).
            func bestSplitLength(for attributedString: NSAttributedString, width: CGFloat, maxHeight: CGFloat) -> Int {
                let lineFit = lineBreakFitLength(for: attributedString, width: width, maxHeight: maxHeight)
                guard lineFit > 0 else { return 0 }
                if lineFit >= attributedString.length { return lineFit }

                let text = attributedString.string as NSString

                if let scalar = UnicodeScalar(text.character(at: lineFit - 1)),
                   CharacterSet.newlines.contains(scalar) {
                    return lineFit
                }

                if splitLeavesCleanFragments(attributedString, splitIndex: lineFit, width: width,
                                             minimumLinesAtBottom: 3, minimumLinesAtTop: 2) {
                    return lineFit
                }

                let cutParagraphStart = text.paragraphRange(for: NSRange(location: lineFit, length: 0)).location
                if cutParagraphStart > 0 {
                    let head = text.substring(to: cutParagraphStart)
                    if !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return cutParagraphStart
                    }
                }

                return lineFit
            }

            // MARK: Body normalization

            /// Marker detection must stay in step with RichTextEditor's
            /// `markerPrefix(in:)` — the editor bakes these exact prefixes into the
            /// text when building lists.
            func listMarkerPrefix(in trimmedParagraph: String) -> String? {
                if trimmedParagraph.hasPrefix("• ") {
                    return "• "
                }
                if let range = trimmedParagraph.range(of: "^\\d+\\.\\s", options: .regularExpression) {
                    return String(trimmedParagraph[range])
                }
                return nil
            }

            func normalizedBodyAttributedString(for attributedString: NSAttributedString, baseFont: UIFont) -> NSAttributedString {
                let mutable = NSMutableAttributedString(attributedString: attributedString)
                let fullRange = NSRange(location: 0, length: mutable.length)
                guard fullRange.length > 0 else { return mutable }

                mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                    let currentFont = (value as? UIFont) ?? baseFont
                    let traits = currentFont.fontDescriptor.symbolicTraits
                    let normalizedDescriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
                    mutable.addAttribute(.font, value: UIFont(descriptor: normalizedDescriptor, size: baseFont.pointSize), range: range)
                }
                mutable.addAttribute(.foregroundColor, value: UIColor.black, range: fullRange)

                // ONE paragraph style per paragraph. List paragraphs get their hanging
                // indent recomputed from the marker's width AT THE PRINT FONT — the
                // editor measured it at the editor font, and system-font glyph widths
                // are not proportional across sizes, so scaling the authored value
                // leaves wrapped lines misaligned.
                let text = mutable.string as NSString
                var location = 0
                while location < mutable.length {
                    let paragraphRange = text.paragraphRange(for: NSRange(location: location, length: 0))
                    guard NSMaxRange(paragraphRange) > location else { break }

                    let authoredFont = (attributedString.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? UIFont) ?? baseFont
                    let authoredStyle = attributedString.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
                    let scale = baseFont.pointSize / max(authoredFont.pointSize, 1)

                    let style = (authoredStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    style.firstLineHeadIndent = (authoredStyle?.firstLineHeadIndent ?? 0) * scale
                    style.tailIndent = (authoredStyle?.tailIndent ?? 0) * scale
                    style.paragraphSpacing = (authoredStyle?.paragraphSpacing ?? 0) * scale
                    style.paragraphSpacingBefore = (authoredStyle?.paragraphSpacingBefore ?? 0) * scale
                    style.lineSpacing = (authoredStyle?.lineSpacing ?? 0) * scale

                    let trimmedParagraph = text.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let marker = listMarkerPrefix(in: trimmedParagraph) {
                        let printFont = (mutable.attribute(.font, at: paragraphRange.location, effectiveRange: nil) as? UIFont) ?? baseFont
                        let markerWidth = ceil((marker as NSString).size(withAttributes: [.font: printFont]).width)
                        style.headIndent = style.firstLineHeadIndent + markerWidth
                    } else {
                        style.headIndent = (authoredStyle?.headIndent ?? 0) * scale
                    }

                    mutable.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
                    location = NSMaxRange(paragraphRange)
                }

                return mutable
            }

            /// A chunk that continues a paragraph split mid-text must resume at the
            /// WRAP column, not back under the list marker: give the tail's first
            /// paragraph a first-line indent equal to its hanging indent.
            func fixContinuationIndent(_ tail: NSMutableAttributedString) {
                guard tail.length > 0 else { return }
                let firstParagraph = (tail.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                guard firstParagraph.length > 0 else { return }
                tail.enumerateAttribute(.paragraphStyle, in: firstParagraph, options: []) { value, range, _ in
                    guard let style = value as? NSParagraphStyle, style.firstLineHeadIndent != style.headIndent else { return }
                    let continued = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    continued.firstLineHeadIndent = continued.headIndent
                    tail.addAttribute(.paragraphStyle, value: continued, range: range)
                }
            }

            // MARK: Page content

            context.beginPage()
            drawLetterhead(on: context)

            let title = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            if !title.isEmpty {
                let titleRect = CGRect(x: contentLeftX, y: y, width: contentWidth, height: 28)
                (title as NSString).draw(
                    in: titleRect,
                    withAttributes: [
                        .font: headingFont,
                        .paragraphStyle: {
                            let style = NSMutableParagraphStyle()
                            style.alignment = .center
                            return style
                        }()
                    ]
                )
                y += 40
            }

            let trimmedPatientName = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPatientName.isEmpty {
                let subheadingLineHeight = ceil(subheadingFont.lineHeight) + 4
                let patientRect = CGRect(x: contentLeftX, y: y, width: contentWidth * 0.6, height: subheadingLineHeight)
                let dateRect = CGRect(x: contentLeftX + (contentWidth * 0.4), y: y, width: contentWidth * 0.6, height: subheadingLineHeight)

                ("Patient: \(trimmedPatientName)" as NSString).draw(in: patientRect, withAttributes: [
                    .font: subheadingFont,
                    .foregroundColor: UIColor.darkGray
                ])

                ("Date of Exam: \(reportDate.formatted(date: .abbreviated, time: .omitted))" as NSString).draw(
                    in: dateRect,
                    withAttributes: [
                        .font: subheadingFont,
                        .foregroundColor: UIColor.darkGray,
                        .paragraphStyle: {
                            let style = NSMutableParagraphStyle()
                            style.alignment = .right
                            return style
                        }()
                    ]
                )

                y += subheadingLineHeight + 10
            }

            for entry in entries {
                let entryTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let bodyAttributed = normalizedBodyAttributedString(for: entry.attributedBody, baseFont: bodyFont)
                let entryBody = bodyAttributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entryTitle.isEmpty || !entryBody.isEmpty else { continue }

                let bodyIndent: CGFloat = 18
                let headerTextInsetX: CGFloat = 12
                let headerTextInsetY: CGFloat = 5
                let headerTextWidth = contentWidth - (headerTextInsetX * 2)
                let headerTextHeight: CGFloat = entryTitle.isEmpty ? 0 : ceil((entryTitle as NSString).boundingRect(
                    with: CGSize(width: headerTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [
                        .font: entryHeaderFont
                    ],
                    context: nil
                ).height)
                let headerHeight: CGFloat = entryTitle.isEmpty ? 0 : max(26, headerTextHeight + (headerTextInsetY * 2))
                let firstChunkHeight: CGFloat = entryBody.isEmpty ? 0 : (bodyLineHeight * 4 + continuationReserve)
                let minimumSectionHeight = headerHeight + (entryTitle.isEmpty ? 0 : 10) + firstChunkHeight

                let availableHeight = contentBottomY - y
                if availableHeight < minimumSectionHeight {
                    context.beginPage()
                    drawLetterhead(on: context)
                    y = contentStartY
                }

                if !entryTitle.isEmpty {
                    let headerRect = CGRect(x: contentLeftX, y: y, width: contentWidth, height: headerHeight)
                    let headerPath = UIBezierPath(roundedRect: headerRect, cornerRadius: 12)

                    UIColor(white: 0.97, alpha: 1.0).setFill()
                    headerPath.fill()

                    UIColor.black.setStroke()
                    headerPath.lineWidth = 2.25
                    headerPath.stroke()

                    let textRect = CGRect(
                        x: headerRect.minX + headerTextInsetX,
                        y: headerRect.minY + headerTextInsetY,
                        width: headerTextWidth,
                        height: headerHeight - (headerTextInsetY * 2)
                    )
                    (entryTitle as NSString).draw(
                        with: textRect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [
                            .font: entryHeaderFont,
                            .foregroundColor: UIColor.black
                        ],
                        context: nil
                    )
                    y += headerHeight + 10
                }

                let bodyWidth = contentWidth - bodyIndent

                if bodyAttributed.length > 0 {
                    var remaining: NSAttributedString = bodyAttributed

                    while remaining.length > 0 {
                        // Whole remainder fits on this page — draw it and finish the entry.
                        let remainingHeight = ceil(remaining.boundingRect(
                            with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            context: nil
                        ).height)
                        if y + remainingHeight <= contentBottomY {
                            remaining.draw(
                                with: CGRect(x: contentLeftX + bodyIndent, y: y, width: bodyWidth, height: remainingHeight + 4),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil
                            )
                            y += remainingHeight + 10
                            break
                        }

                        let pageIsFresh = y <= contentStartY + 0.5
                        let availableBodyHeight = contentBottomY - continuationReserve - y
                        if availableBodyHeight < bodyLineHeight * 2 && !pageIsFresh {
                            continueOnNextPage()
                            continue
                        }

                        var fitLength = bestSplitLength(for: remaining, width: bodyWidth, maxHeight: availableBodyHeight)
                        if fitLength == 0 {
                            if !pageIsFresh {
                                continueOnNextPage()
                                continue
                            }
                            // A fresh page can't hold even one line (pathological safe
                            // zone): force the first line and let it overflow rather
                            // than page-break forever.
                            fitLength = firstLineLength(of: remaining, width: bodyWidth)
                            if fitLength == 0 { break }
                        }

                        let text = remaining.string as NSString

                        // Don't draw the split's trailing whitespace at the page bottom.
                        var headEnd = fitLength
                        while headEnd > 0,
                              let scalar = UnicodeScalar(text.character(at: headEnd - 1)),
                              CharacterSet.whitespacesAndNewlines.contains(scalar) {
                            headEnd -= 1
                        }

                        if headEnd > 0 {
                            let chunk = remaining.attributedSubstring(from: NSRange(location: 0, length: headEnd))
                            let usedRect = chunk.boundingRect(
                                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil
                            )
                            chunk.draw(
                                with: CGRect(x: contentLeftX + bodyIndent, y: y, width: bodyWidth, height: ceil(usedRect.height) + 4),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil
                            )
                            y += ceil(usedRect.height) + 10
                        }

                        // Advance past the whitespace consumed by the split, noting
                        // whether a paragraph break was crossed.
                        var tailStart = fitLength
                        while tailStart < remaining.length,
                              let scalar = UnicodeScalar(text.character(at: tailStart)),
                              CharacterSet.whitespacesAndNewlines.contains(scalar) {
                            tailStart += 1
                        }
                        guard tailStart < remaining.length else { break }

                        var crossedParagraphBreak = false
                        for index in headEnd..<tailStart {
                            if let scalar = UnicodeScalar(text.character(at: index)),
                               CharacterSet.newlines.contains(scalar) {
                                crossedParagraphBreak = true
                                break
                            }
                        }

                        let tail = NSMutableAttributedString(
                            attributedString: remaining.attributedSubstring(
                                from: NSRange(location: tailStart, length: remaining.length - tailStart)
                            )
                        )
                        if !crossedParagraphBreak {
                            fixContinuationIndent(tail)
                        }
                        remaining = tail

                        continueOnNextPage()
                    }
                }
            }
        }

        if let document = PDFDocument(url: outputURL) {
            let pageCount = document.pageCount
            let numberRenderer = UIGraphicsPDFRenderer(bounds: pageRect)

            try numberRenderer.writePDF(to: numberedOutputURL) { context in
                for pageIndex in 0..<pageCount {
                    context.beginPage()

                    if let page = document.page(at: pageIndex) {
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: 0, y: pageRect.height)
                        cg.scaleBy(x: 1, y: -1)
                        page.draw(with: .mediaBox, to: cg)
                        cg.restoreGState()
                    }

                    let pageLabel = "Page \(pageIndex + 1) of \(pageCount)"
                    if let origin = safeZoneConfig?.pageNumberOrigin {
                        let p = CGPoint(x: origin.x * W, y: origin.y * H)
                        (pageLabel as NSString).draw(
                            at: p,
                            withAttributes: [
                                .font: UIFont.systemFont(ofSize: 9),
                                .foregroundColor: UIColor.darkGray
                            ]
                        )
                    } else {
                        let footerFont = UIFont.systemFont(ofSize: 10)
                        let footerRect = CGRect(x: 54, y: pageRect.height - 78, width: pageRect.width - 108, height: 14)
                        (pageLabel as NSString).draw(
                            in: footerRect,
                            withAttributes: [
                                .font: footerFont,
                                .foregroundColor: UIColor.darkGray,
                                .paragraphStyle: {
                                    let style = NSMutableParagraphStyle()
                                    style.alignment = .right
                                    return style
                                }()
                            ]
                        )
                    }
                }
            }

            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.moveItem(at: numberedOutputURL, to: outputURL)
        }
        return outputURL
    }
}
