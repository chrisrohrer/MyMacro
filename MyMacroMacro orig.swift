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



public struct SynthCodableMacro: MemberMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // Make sure you're dealing with a struct declaration
        guard let structDecl = decl.as(StructDeclSyntax.self) else {
            return []
        }

        // Check if the struct conforms to a specific protocol (optional)
//        guard protocols.contains(where: { $0.description == "Codable" }) else {
//            return [
//                DeclSyntax(stringLiteral: "error")
//            ]
//        }

        var codingKeys: [String] = []
        var initFromDecoderStatements: [String] = []
        var encodeStatements: [String] = []
        
        // Loop through members of the struct
        for member in structDecl.memberBlock.members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            
            let propertyName = identifier.identifier.text

            // Check if the property is marked with @Relation by looking through attributes
            
            var isRelation = false
            if let attribute = variableDecl.attributes.first?.as(AttributeSyntax.self) {
                isRelation = attribute.attributeName.description.contains("Relation")
            }

            
            if let typeAnnotation = binding.typeAnnotation {
                let propertyType = typeAnnotation.type.description
                
                // Always add to CodingKeys
                codingKeys.append("case \(propertyName) = \"\(propertyName.camelCaseToSnakeCase())\"")
                
                // Generate decoding logic
                initFromDecoderStatements.append("self.\(propertyName) = try container.decode(\(propertyType).self, forKey: .\(propertyName))")

                // Skip encoding logic for @Relation properties
                if !isRelation {
                    encodeStatements.append("try container.encode(\(propertyName), forKey: .\(propertyName))")
                }
            }
        }

        let codingKeysDecl = """
        enum CodingKeys: String, CodingKey {
            \(codingKeys.joined(separator: "\n"))
        }
        """
        
        let initFromDecoderDecl = """
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            \(initFromDecoderStatements.joined(separator: "\n"))
        }
        """
        
        let encodeDecl = """
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            \(encodeStatements.joined(separator: "\n"))
        }
        """

        return [
            DeclSyntax(stringLiteral: codingKeysDecl),
            DeclSyntax(stringLiteral: initFromDecoderDecl),
            DeclSyntax(stringLiteral: encodeDecl)
        ]
    }
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
