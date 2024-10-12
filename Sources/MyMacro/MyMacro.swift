// The Swift Programming Language
// https://docs.swift.org/swift-book


@attached(member, names: arbitrary)
public macro SynthCodable() = #externalMacro(module: "MyMacroMacros", type: "SynthCodableMacro")

