enum GlassConfig {
    enum Mode { case automatic, material }
    enum Variant { case white, transparent }

    static let mode: Mode = .automatic
    static let variant: Variant = .white
}