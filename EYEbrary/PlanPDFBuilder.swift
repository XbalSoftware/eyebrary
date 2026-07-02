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
        safeZoneConfig: SafeZoneConfig?
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

            func fittingLength(for attributedString: NSAttributedString, width: CGFloat, maxHeight: CGFloat) -> Int {
                guard attributedString.length > 0, maxHeight > 0 else { return 0 }

                var low = 0
                var high = attributedString.length
                var best = 0

                while low <= high {
                    let mid = (low + high) / 2
                    let testRange = NSRange(location: 0, length: mid)
                    let testString = attributedString.attributedSubstring(from: testRange)
                    let rect = testString.boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )

                    if ceil(rect.height) <= maxHeight {
                        best = mid
                        low = mid + 1
                    } else {
                        high = mid - 1
                    }
                }

                return best
            }

            func splitCreatesWidowOrOrphan(
                for attributedString: NSAttributedString,
                splitLength: Int,
                width: CGFloat,
                bodyFont: UIFont,
                minimumLinesAtBottom: Int = 3,
                minimumLinesAtTop: Int = 2
            ) -> Bool {
                guard splitLength > 0, splitLength < attributedString.length else { return false }

                let lineHeight = ceil(bodyFont.lineHeight)
                let minimumBottomHeight = CGFloat(minimumLinesAtBottom) * lineHeight
                let minimumTopHeight = CGFloat(minimumLinesAtTop) * lineHeight

                let bottomRect = attributedString.attributedSubstring(from: NSRange(location: 0, length: splitLength)).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let topRect = attributedString.attributedSubstring(from: NSRange(location: splitLength, length: attributedString.length - splitLength)).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                return ceil(bottomRect.height) < minimumBottomHeight || ceil(topRect.height) < minimumTopHeight
            }
            func bestSplitLength(
                for attributedString: NSAttributedString,
                width: CGFloat,
                maxHeight: CGFloat,
                bodyFont: UIFont,
                minimumLinesAtBottom: Int = 3,
                minimumLinesAtTop: Int = 2
            ) -> Int {
                let rawFit = fittingLength(for: attributedString, width: width, maxHeight: maxHeight)
                guard rawFit > 0 else { return 0 }

                if rawFit >= attributedString.length {
                    return rawFit
                }

                let text = attributedString.string as NSString
                let candidateRange = NSRange(location: 0, length: rawFit)

                var candidates: [Int] = [rawFit]

                let sentenceRange = text.range(of: ". ", options: .backwards, range: candidateRange)
                if sentenceRange.location != NSNotFound, sentenceRange.location > 0 {
                    candidates.append(sentenceRange.location + 1)
                }

                let whitespaceRange = text.rangeOfCharacter(
                    from: .whitespacesAndNewlines,
                    options: .backwards,
                    range: candidateRange
                )
                if whitespaceRange.location != NSNotFound, whitespaceRange.location > 0 {
                    candidates.append(whitespaceRange.location)
                }

                let sortedCandidates = candidates.sorted(by: >)

                // 1. Strict rule (3 / 2)
                for candidate in sortedCandidates {
                    guard candidate > 0 else { continue }
                    if candidate >= attributedString.length { return candidate }

                    if !splitCreatesWidowOrOrphan(
                        for: attributedString,
                        splitLength: candidate,
                        width: width,
                        bodyFont: bodyFont,
                        minimumLinesAtBottom: minimumLinesAtBottom,
                        minimumLinesAtTop: minimumLinesAtTop
                    ) {
                        return candidate
                    }
                }

                // 2. Fallback rule (2 / 2)
                for candidate in sortedCandidates {
                    guard candidate > 0 else { continue }
                    if candidate >= attributedString.length { return candidate }

                    if !splitCreatesWidowOrOrphan(
                        for: attributedString,
                        splitLength: candidate,
                        width: width,
                        bodyFont: bodyFont,
                        minimumLinesAtBottom: 2,
                        minimumLinesAtTop: 2
                    ) {
                        return candidate
                    }
                }

                // 3. Final fallback — avoid only a single-line orphan
                let lineHeight = ceil(bodyFont.lineHeight)

                for candidate in sortedCandidates {
                    guard candidate > 0 else { continue }
                    if candidate >= attributedString.length { return candidate }

                    let bottomRect = attributedString.attributedSubstring(
                        from: NSRange(location: 0, length: candidate)
                    ).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )

                    if ceil(bottomRect.height) >= lineHeight {
                        return candidate
                    }
                }

                return 0
            }
            func normalizedBodyAttributedString(for attributedString: NSAttributedString, baseFont: UIFont) -> NSAttributedString {
                let mutable = NSMutableAttributedString(attributedString: attributedString)
                let fullRange = NSRange(location: 0, length: mutable.length)

                guard fullRange.length > 0 else { return mutable }

                mutable.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
                    let currentFont = (attrs[.font] as? UIFont) ?? baseFont
                    let descriptor = currentFont.fontDescriptor
                    let traits = descriptor.symbolicTraits
                    let normalizedDescriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
                    let normalizedFont = UIFont(descriptor: normalizedDescriptor, size: baseFont.pointSize)

                    mutable.addAttribute(.font, value: normalizedFont, range: range)
                    mutable.addAttribute(.foregroundColor, value: UIColor.black, range: range)

                    if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                        let style = (paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                        let scale = max(0.01, baseFont.pointSize / max(currentFont.pointSize, 0.01))
                        style.firstLineHeadIndent *= scale
                        style.headIndent *= scale
                        style.tailIndent *= scale
                        style.paragraphSpacing *= scale
                        style.paragraphSpacingBefore *= scale
                        style.lineSpacing *= scale
                        mutable.addAttribute(.paragraphStyle, value: style, range: range)
                    }
                }

                return mutable
            }

            func drawContinuationNote() {
                let note = "Continued on next page"
                let noteRect = CGRect(x: contentLeftX + 18, y: contentBottomY - continuationReserve, width: contentWidth - 18, height: 12)
                (note as NSString).draw(in: noteRect, withAttributes: [
                    .font: continuationFont,
                    .foregroundColor: UIColor.darkGray
                ])
            }

            context.beginPage()
            drawLetterhead(on: context)

            var y: CGFloat = contentStartY

            let title = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let headingFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let subheadingFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 10)
            let continuationFont = UIFont.italicSystemFont(ofSize: 9)

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
                let patientRect = CGRect(x: contentLeftX, y: y, width: contentWidth * 0.6, height: 18)
                let dateRect = CGRect(x: contentLeftX + (contentWidth * 0.4), y: y, width: contentWidth * 0.6, height: 18)

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

                y += 28
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
                        .font: UIFont.systemFont(ofSize: 12, weight: .bold)
                    ],
                    context: nil
                ).height)
                let headerHeight: CGFloat = entryTitle.isEmpty ? 0 : max(26, headerTextHeight + (headerTextInsetY * 2))
                let firstChunkHeight: CGFloat = entryBody.isEmpty ? 0 : 56
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
                            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                            .foregroundColor: UIColor.black
                        ],
                        context: nil
                    )
                    y += headerHeight + 10
                }

                let bodyWidth = contentWidth - bodyIndent
                let fullBodyString = bodyAttributed

                if fullBodyString.length > 0 {
                    let fullBodyRect = fullBodyString.boundingRect(
                        with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    let fullBodyHeight = ceil(fullBodyRect.height)

                    if y + fullBodyHeight <= contentBottomY {
                        fullBodyString.draw(
                            with: CGRect(x: contentLeftX + bodyIndent, y: y, width: bodyWidth, height: fullBodyHeight + 4),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            context: nil
                        )
                        y += fullBodyHeight + 10
                    } else {
                        var drawLocation = 0
                        let bodyNSString = fullBodyString.string as NSString

                        while drawLocation < fullBodyString.length {
                            let availableBodyHeight = contentBottomY - continuationReserve - y
                            if availableBodyHeight < 24 {
                                drawContinuationNote()
                                context.beginPage()
                                drawLetterhead(on: context)
                                y = contentStartY
                                continue
                            }

                            let remainingRange = NSRange(location: drawLocation, length: fullBodyString.length - drawLocation)
                            let remainingString = fullBodyString.attributedSubstring(from: remainingRange)
                            let fitLength = bestSplitLength(
                                for: remainingString,
                                width: bodyWidth,
                                maxHeight: availableBodyHeight,
                                bodyFont: bodyFont,
                                minimumLinesAtBottom: 3,
                                minimumLinesAtTop: 2
                            )

                            if fitLength == 0 {
                                drawContinuationNote()
                                context.beginPage()
                                drawLetterhead(on: context)
                                y = contentStartY
                                continue
                            }

                            let drawRange = NSRange(location: drawLocation, length: fitLength)
                            let chunk = fullBodyString.attributedSubstring(from: drawRange)
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
                            drawLocation += fitLength

                            while drawLocation < fullBodyString.length {
                                let scalar = bodyNSString.character(at: drawLocation)
                                if let unicode = UnicodeScalar(scalar), CharacterSet.whitespacesAndNewlines.contains(unicode) {
                                    drawLocation += 1
                                } else {
                                    break
                                }
                            }

                            if drawLocation < fullBodyString.length {
                                drawContinuationNote()
                                context.beginPage()
                                drawLetterhead(on: context)
                                y = contentStartY
                            }
                        }
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
