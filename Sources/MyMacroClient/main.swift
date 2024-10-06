import MyMacro
import Foundation

let a = 17
let b = 25

let (result, code) = #stringify(a + b)

//let (x, y) = #stringify(4)

print("The value \(result) was produced by the code \"\(code)\"")


@propertyWrapper
struct Relation<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

@propertyWrapper
struct ForeignKey<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}



@SynthCodable
struct Book: Codable {
    
    var id: Int?
    var createdAt: Date = .now
    var title: String
    var pages: Int
    
    @ForeignKey var authorId: Int?
    
    @Relation var author: Author?
    
}



@SynthCodable
struct Author: Codable {
    
    var id: Int?
    var createdAt: Date = .now
    var name: String
    var birthyear: Int
    
    @ForeignKey var countryId: Int?
    
    @Relation var books: [Book] = []
    @Relation var country: Country?
    
}



@SynthCodable
struct Country: Codable {
    
    static let tableName = "Author"
    
    var id: Int?
    var createdAt: Date = .now
    var name: String
    
    @Relation var authors: [Author] = []
    
}
