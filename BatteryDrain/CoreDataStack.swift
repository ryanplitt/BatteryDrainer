import CoreData
import Foundation

// MARK: - Core Data Stress Model
@objc(StressTestEntity)
public class StressTestEntity: NSManagedObject {
    @NSManaged public var id: Int32
    @NSManaged public var name: String
    @NSManaged public var value: Double
    @NSManaged public var timestamp: Date
    @NSManaged public var largeData: Data
}

extension StressTestEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<StressTestEntity> {
        return NSFetchRequest<StressTestEntity>(entityName: "StressTestEntity")
    }
}

// MARK: - Core Data Stack for Battery Stress Testing
class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var persistentContainer: NSPersistentContainer = {
        // Create programmatic model since we don't have .xcdatamodeld
        let model = NSManagedObjectModel()
        
        // Create entity
        let entity = NSEntityDescription()
        entity.name = "StressTestEntity"
        entity.managedObjectClassName = "StressTestEntity"
        
        // Add attributes
        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .integer32AttributeType
        idAttribute.isOptional = false
        
        let nameAttribute = NSAttributeDescription()
        nameAttribute.name = "name"
        nameAttribute.attributeType = .stringAttributeType
        nameAttribute.isOptional = false
        
        let valueAttribute = NSAttributeDescription()
        valueAttribute.name = "value"
        valueAttribute.attributeType = .doubleAttributeType
        valueAttribute.isOptional = false
        
        let timestampAttribute = NSAttributeDescription()
        timestampAttribute.name = "timestamp"
        timestampAttribute.attributeType = .dateAttributeType
        timestampAttribute.isOptional = false
        
        let dataAttribute = NSAttributeDescription()
        dataAttribute.name = "largeData"
        dataAttribute.attributeType = .binaryDataAttributeType
        dataAttribute.isOptional = false
        
        entity.properties = [idAttribute, nameAttribute, valueAttribute, timestampAttribute, dataAttribute]
        model.entities = [entity]
        
        let container = NSPersistentContainer(name: "BatteryStressModel", managedObjectModel: model)
        
        // Create in-memory store for maximum performance stress
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                print("Core Data error: \(error)")
            }
        }
        
        // Configure for maximum performance load
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func saveContext() {
        let context = persistentContainer.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Core Data save error: \(error)")
            }
        }
    }
}