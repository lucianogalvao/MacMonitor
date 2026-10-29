// Lista os sensores de temperatura expostos via IOHID (Apple Silicon).
// Uso: swift Scripts/sensors-probe.swift
import Foundation

// Funções privadas do IOKit, carregadas em tempo de execução.
let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

func load<T>(_ name: String, as type: T.Type) -> T {
    guard let symbol = dlsym(iokit, name) else { fatalError("Símbolo não encontrado: \(name)") }
    return unsafeBitCast(symbol, to: type)
}

typealias ClientCreate = @convention(c) (CFAllocator?) -> OpaquePointer?
typealias ClientSetMatching = @convention(c) (OpaquePointer, CFDictionary) -> Int32
typealias ClientCopyServices = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
typealias ServiceCopyProperty = @convention(c) (OpaquePointer, CFString) -> Unmanaged<CFTypeRef>?
typealias ServiceCopyEvent = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
typealias EventGetFloat = @convention(c) (OpaquePointer, Int32) -> Double

let createClient = load("IOHIDEventSystemClientCreate", as: ClientCreate.self)
let setMatching = load("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self)
let copyServices = load("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self)
let copyProperty = load("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self)
let copyEvent = load("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self)
let getFloat = load("IOHIDEventGetFloatValue", as: EventGetFloat.self)

let temperatureEvent: Int64 = 15 // kIOHIDEventTypeTemperature
let temperatureField = Int32(temperatureEvent << 16)

guard let client = createClient(kCFAllocatorDefault) else { fatalError("Não foi possível criar o cliente HID") }
_ = setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)

let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
var readings: [(String, Double)] = []
for service in services {
    let pointer = OpaquePointer(Unmanaged.passUnretained(service).toOpaque())
    let name = copyProperty(pointer, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
    guard let event = copyEvent(pointer, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
    let value = getFloat(OpaquePointer(Unmanaged.passUnretained(event).toOpaque()), temperatureField)
    readings.append((name, value))
}

print("\(readings.count) sensores (de \(services.count) serviços)\n")
for (name, value) in readings.sorted(by: { $0.0 < $1.0 }) {
    print(String(format: "%-34@ %6.1f °C", name as NSString, value))
}
