import AppKit

/// The `NSSavePanel` accessory view for "Zapisz jako…": a format picker
/// plus, only "gdzie to się stosuje" (where it actually applies to that
/// format's encoder), a quality slider or a compression choice — nothing
/// shown at all for PNG/BMP/GIF, which have no meaningful save-time option
/// beyond the format itself.
///
/// Built in plain AppKit — `NSStackView` + `NSPopUpButton`/`NSSlider` driven
/// by target/action — rather than as a SwiftUI view bridged in through
/// `NSHostingView`. A SwiftUI `Picker` embedded that way inside
/// `NSSavePanel.accessoryView` turned out to be a genuinely unreliable
/// combination: even with an explicit frame and `.intrinsicContentSize` set
/// on the hosting view up front, the popup menu stayed unresponsive to the
/// first click and only "caught up" once something else forced a relayout
/// (e.g. pressing Save once and having the panel reject the attempt,
/// exactly as reported). A plain `NSPopUpButton` has no such bridge to go
/// through and is clickable the instant the panel appears.
final class SaveOptionsAccessoryView: NSView {

    private(set) var format: SupportedImageTypes.WritableFormat {
        didSet { applyVisibility() }
    }
    private(set) var quality: Double = 0.9
    private(set) var tiffUseLZW: Bool = true

    /// Fires on every change to `format`/`quality`/`tiffUseLZW` so
    /// `ImageViewerViewModel.presentSaveAsPanel()` can keep the panel's
    /// `allowedContentTypes` and file-name extension in sync live, the same
    /// way the old Combine-based `$format` subscription did.
    var onChange: (() -> Void)?

    var exportOptions: ImageExporter.SaveOptions {
        ImageExporter.SaveOptions(format: format, quality: quality, tiffUseLZW: tiffUseLZW)
    }

    private let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualitySlider = NSSlider(value: 0.9, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)
    private let qualityValueLabel = NSTextField(labelWithString: "90%")
    private let qualityGroup = NSStackView()
    private let compressionPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let compressionGroup = NSStackView()

    init(initialFormat: SupportedImageTypes.WritableFormat) {
        format = initialFormat
        super.init(frame: .zero)
        buildUI()
        applyVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private func buildUI() {
        // Format row.
        formatPopUp.target = self
        formatPopUp.action = #selector(formatPopUpChanged(_:))
        for candidate in SupportedImageTypes.WritableFormat.allCases {
            formatPopUp.addItem(withTitle: candidate.displayName)
        }
        formatPopUp.selectItem(withTitle: format.displayName)
        let formatLabel = NSTextField(labelWithString: String(localized: "Format:", comment: "Label before the format picker in the Save As accessory view"))
        let formatRow = NSStackView(views: [formatLabel, formatPopUp])
        formatRow.orientation = .horizontal
        formatRow.spacing = 8
        formatRow.alignment = .centerY

        // Quality row — shown only for JPEG/HEIC.
        qualitySlider.target = self
        qualitySlider.action = #selector(qualitySliderChanged(_:))
        qualitySlider.doubleValue = quality
        let qualityLabel = NSTextField(labelWithString: String(localized: "Jakość:", comment: "Label before the quality slider in the Save As accessory view"))
        qualityValueLabel.alignment = .right
        qualityValueLabel.stringValue = "\(Int(quality * 100))%"
        let qualitySpacer = NSView()
        qualitySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let qualityHeaderRow = NSStackView(views: [qualityLabel, qualitySpacer, qualityValueLabel])
        qualityHeaderRow.orientation = .horizontal
        qualityHeaderRow.spacing = 4
        qualityGroup.orientation = .vertical
        qualityGroup.alignment = .leading
        qualityGroup.spacing = 4
        qualityGroup.addArrangedSubview(qualityHeaderRow)
        qualityGroup.addArrangedSubview(qualitySlider)

        // Compression row — shown only for TIFF.
        compressionPopUp.target = self
        compressionPopUp.action = #selector(compressionPopUpChanged(_:))
        compressionPopUp.addItem(withTitle: String(localized: "LZW (bezstratna)", comment: "TIFF compression option: lossless LZW"))
        compressionPopUp.addItem(withTitle: String(localized: "Brak", comment: "TIFF compression option: none"))
        compressionPopUp.selectItem(at: tiffUseLZW ? 0 : 1)
        let compressionLabel = NSTextField(labelWithString: String(localized: "Kompresja:", comment: "Label before the TIFF compression picker in the Save As accessory view"))
        compressionGroup.orientation = .horizontal
        compressionGroup.spacing = 8
        compressionGroup.alignment = .centerY
        compressionGroup.addArrangedSubview(compressionLabel)
        compressionGroup.addArrangedSubview(compressionPopUp)

        let mainStack = NSStackView(views: [formatRow, qualityGroup, compressionGroup])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        // A fixed content width (matching the old SwiftUI layout's 220pt
        // rows plus 16pt padding on each side) keeps the panel from
        // resizing sideways as rows hide/show — only the height changes,
        // which `NSStackView` already handles by collapsing a hidden
        // arranged subview's space automatically. Self's own height is
        // left undetermined here on purpose: it's fully resolved by this
        // constraint chain (top/bottom pins to `mainStack` plus
        // `mainStack`'s own content height), giving `NSSavePanel` a
        // correct `fittingSize` to lay the panel out around.
        let contentWidth: CGFloat = 220
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.widthAnchor.constraint(equalToConstant: contentWidth),
            widthAnchor.constraint(equalToConstant: contentWidth + 32),
            formatRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            qualityGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            compressionGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            qualityHeaderRow.widthAnchor.constraint(equalTo: qualityGroup.widthAnchor),
            qualitySlider.widthAnchor.constraint(equalTo: qualityGroup.widthAnchor)
        ])
    }

    private func applyVisibility() {
        qualityGroup.isHidden = !format.supportsQuality
        compressionGroup.isHidden = !format.supportsCompressionChoice
    }

    // MARK: Actions

    @objc private func formatPopUpChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SupportedImageTypes.WritableFormat.allCases.indices.contains(index) else { return }
        format = SupportedImageTypes.WritableFormat.allCases[index]
        onChange?()
    }

    @objc private func qualitySliderChanged(_ sender: NSSlider) {
        quality = sender.doubleValue
        qualityValueLabel.stringValue = "\(Int(quality * 100))%"
        onChange?()
    }

    @objc private func compressionPopUpChanged(_ sender: NSPopUpButton) {
        tiffUseLZW = sender.indexOfSelectedItem == 0
        onChange?()
    }
}
