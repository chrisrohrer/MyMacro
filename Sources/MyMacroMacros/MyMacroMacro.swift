import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

import Foundation

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.argumentList.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }
        
        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct MyMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        SynthCodableMacro.self
    ]
}

// Helper function to convert camelCase to snake_case
extension String {
    func camelCaseToSnakeCase() -> String {
        return unicodeScalars.reduce("") {
            CharacterSet.uppercaseLetters.contains($1)
            ? $0 + "_" + String($1).lowercased()
            : $0 + String($1)
        }
    }
}

// Helper function to get the type name from the type annotation
func getTypeName(_ type: String) -> String {
    return type
        .replacingOccurrences(of: "?", with: "")
        .replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
        .replacingOccurrences(of: " ", with: "")
}



public struct SynthCodableMacro: MemberMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let structDecl = decl.as(StructDeclSyntax.self) else {
            return []
        }
        
//        guard protocols.contains(where: { $0.description.contains("Codable") }) else {
//            return []
//        }

        var codingKeys: [String] = []
        var initFromDecoderStatements: [String] = []
        var encodeStatements: [String] = []
        var convenienceInitParameters: [String] = []
        var convenienceInitAssignments: [String] = []

        // Loop through the struct's members to identify properties
        for member in structDecl.memberBlock.members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            
            let propertyName = identifier.identifier.text
            
            // Check if the property is marked as static
            let isStatic = variableDecl.modifiers.contains(where: { $0.name.text.contains("static") })
            if isStatic {
                // Skip encoding and decoding for static properties
                continue
            }

            // Check if the property is marked with @Relation or @ForeignKey
            let isRelation = variableDecl.attributes.contains { attribute in
                if let attributeSyntax = attribute.as(AttributeSyntax.self) {
                    return attributeSyntax.attributeName.description.contains("Relation")
                }
                return false
            }
            let isForeignKey = variableDecl.attributes.contains { attribute in
                if let attributeSyntax = attribute.as(AttributeSyntax.self) {
                    return attributeSyntax.attributeName.description.contains("ForeignKey")
                }
                return false
            }

            if let typeAnnotation = binding.typeAnnotation {
                let propertyType = typeAnnotation.type.description
                let nonOptionalPropertyType = propertyType.replacingOccurrences(of: "?", with: "")
                let typeName = getTypeName(propertyType)

                // Always add to CodingKeys for decoding
                // Handle relation properties and use the type name as the CodingKey
                if isRelation {
                    codingKeys.append("case \(propertyName) = \"\(typeName)\"")
                } else {
                    codingKeys.append("case \(propertyName) = \"\(propertyName.camelCaseToSnakeCase())\"")
                }


                // Handle id property with encodeIfPresent
                if propertyName == "id" {
                    encodeStatements.append("try container.encodeIfPresent(id, forKey: .id)")
                    initFromDecoderStatements.append("self.id = try container.decodeIfPresent(Int.self, forKey: .id)")
                }
                // Handle relation properties (decode only)
                else if isRelation {
                    // For collections like `books`, provide a default empty array ([])
                    if propertyType.hasPrefix("[") {
                        initFromDecoderStatements.append("self.\(propertyName) = try container.decodeIfPresent(\(nonOptionalPropertyType).self, forKey: .\(propertyName)) ?? []")
                    } else {
                        initFromDecoderStatements.append("self.\(propertyName) = try container.decodeIfPresent(\(nonOptionalPropertyType).self, forKey: .\(propertyName))")
                    }
                }
                // Handle foreign key properties (decode as non-optional, e.g., Int.self)
                else if isForeignKey {
                    initFromDecoderStatements.append("self.\(propertyName) = try container.decode(\(propertyType).self, forKey: .\(propertyName))")
                    encodeStatements.append("try container.encodeIfPresent(\(propertyName), forKey: .\(propertyName))")
                }
                // Regular attributes
                else {
                    initFromDecoderStatements.append("self.\(propertyName) = try container.decode(\(propertyType).self, forKey: .\(propertyName))")
                    encodeStatements.append("try container.encode(\(propertyName), forKey: .\(propertyName))")

                    // Add to convenience initializer if it's a regular property
                    convenienceInitParameters.append("\(propertyName): \(propertyType)")
                    convenienceInitAssignments.append("self.\(propertyName) = \(propertyName)")
                }
            }
        }

        // Generate CodingKeys enum
        let codingKeysDecl = """
        enum CodingKeys: String, CodingKey {
            \(codingKeys.joined(separator: "\n"))
        }
        """
        
        // Generate init(from:) method for decoding
        let initFromDecoderDecl = """
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            \(initFromDecoderStatements.joined(separator: "\n"))
        }
        """
        
        // Generate encode(to:) method
        let encodeDecl = """
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            \(encodeStatements.joined(separator: "\n"))
        }
        """

        // Generate convenience initializer
        let convenienceInitDecl = """
        init(\(convenienceInitParameters.joined(separator: ", "))) {
            \(convenienceInitAssignments.joined(separator: "\n"))
        }
        """

        return [
            DeclSyntax(stringLiteral: codingKeysDecl),
            DeclSyntax(stringLiteral: initFromDecoderDecl),
            DeclSyntax(stringLiteral: encodeDecl),
            DeclSyntax(stringLiteral: convenienceInitDecl)
        ]
    }
}
