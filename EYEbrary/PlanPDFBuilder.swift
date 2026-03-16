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
        letterheadURL: URL?
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary-Report.pdf")
        let numberedOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary-Report-Numbered.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let contentStartY: CGFloat = 112
        let contentBottomY: CGFloat = pageRect.height - 120
        let continuationReserve: CGFloat = 18

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

            func drawContinuationNote() {
                let note = "Continued on next page"
                let noteRect = CGRect(x: margin + 18, y: contentBottomY - continuationReserve, width: contentWidth - 18, height: 12)
                (note as NSString).draw(in: noteRect, withAttributes: [
                    .font: continuationFont,
                    .foregroundColor: UIColor.darkGray
                ])
            }

            context.beginPage()
            drawLetterhead(on: context)

            let margin: CGFloat = 54
            var y: CGFloat = contentStartY
            let contentWidth = pageRect.width - (margin * 2)

            let title = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Eye Exam Summary" : reportTitle
            let headingFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let subheadingFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 10)
            let continuationFont = UIFont.italicSystemFont(ofSize: 9)

            let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: 28)
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

            let trimmedPatientName = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPatientName.isEmpty {
                let patientRect = CGRect(x: margin, y: y, width: contentWidth * 0.6, height: 18)
                let dateRect = CGRect(x: margin + (contentWidth * 0.4), y: y, width: contentWidth * 0.6, height: 18)

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
                let entryBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entryTitle.isEmpty || !entryBody.isEmpty else { continue }

                let headerHeight: CGFloat = entryTitle.isEmpty ? 0 : 26
                let bodyIndent: CGFloat = 18
                let firstChunkHeight: CGFloat = entryBody.isEmpty ? 0 : 56
                let minimumSectionHeight = headerHeight + (entryTitle.isEmpty ? 0 : 10) + firstChunkHeight

                let availableHeight = contentBottomY - y
                if availableHeight < minimumSectionHeight {
                    context.beginPage()
                    drawLetterhead(on: context)
                    y = contentStartY
                }

                if !entryTitle.isEmpty {
                    let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: headerHeight)
                    let headerPath = UIBezierPath(roundedRect: headerRect, cornerRadius: 12)

                    UIColor(white: 0.97, alpha: 1.0).setFill()
                    headerPath.fill()

                    UIColor.black.setStroke()
                    headerPath.lineWidth = 2.25
                    headerPath.stroke()

                    let textRect = headerRect.insetBy(dx: 12, dy: 5)
                    (entryTitle as NSString).draw(in: textRect, withAttributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: UIColor.black
                    ])
                    y += headerHeight + 10
                }

                let bodyWidth = contentWidth - bodyIndent
                let bodyAttributes: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ]
                let bodyParagraphs = entryBody.components(separatedBy: .newlines)

                for (index, paragraph) in bodyParagraphs.enumerated() {
                    if paragraph.isEmpty {
                        y += 6
                        continue
                    }

                    let paragraphString = NSAttributedString(string: paragraph, attributes: bodyAttributes)
                    let paragraphRect = paragraphString.boundingRect(
                        with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    let paragraphHeight = ceil(paragraphRect.height)

                    if y + paragraphHeight > contentBottomY - continuationReserve {
                        let freshPageAvailableHeight = contentBottomY - contentStartY

                        if paragraphHeight <= freshPageAvailableHeight {
                            drawContinuationNote()
                            context.beginPage()
                            drawLetterhead(on: context)
                            y = contentStartY
                        } else {
                            let fullBodyString = paragraphString
                            var drawLocation = 0
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
                                var fitLength = fittingLength(for: remainingString, width: bodyWidth, maxHeight: availableBodyHeight)

                                if fitLength == 0 {
                                    drawContinuationNote()
                                    context.beginPage()
                                    drawLetterhead(on: context)
                                    y = contentStartY
                                    continue
                                }

                                if drawLocation + fitLength < fullBodyString.length {
                                    let remainingText = fullBodyString.string as NSString
                                    let candidateRange = NSRange(location: drawLocation, length: fitLength)
                                    let whitespaceRange = remainingText.rangeOfCharacter(
                                        from: .whitespacesAndNewlines,
                                        options: .backwards,
                                        range: candidateRange
                                    )
                                    if whitespaceRange.location != NSNotFound, whitespaceRange.location > drawLocation {
                                        fitLength = whitespaceRange.location - drawLocation
                                    }
                                }

                                let drawRange = NSRange(location: drawLocation, length: fitLength)
                                let chunk = fullBodyString.attributedSubstring(from: drawRange)
                                let chunkRect = CGRect(x: margin + bodyIndent, y: y, width: bodyWidth, height: availableBodyHeight)
                                let usedRect = chunk.boundingRect(
                                    with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    context: nil
                                )
                                chunk.draw(
                                    with: CGRect(x: chunkRect.minX, y: chunkRect.minY, width: bodyWidth, height: ceil(usedRect.height) + 4),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    context: nil
                                )
                                y += ceil(usedRect.height) + 18
                                drawLocation += fitLength

                                while drawLocation < fullBodyString.length {
                                    let scalar = (fullBodyString.string as NSString).character(at: drawLocation)
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

                            if index < bodyParagraphs.count - 1 {
                                y += 4
                            }
                            continue
                        }
                    }

                    paragraphString.draw(
                        with: CGRect(x: margin + bodyIndent, y: y, width: bodyWidth, height: paragraphHeight + 4),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    y += paragraphHeight + 2
                }
                y += 10
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

            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.moveItem(at: numberedOutputURL, to: outputURL)
        }
        return outputURL
    }
}
