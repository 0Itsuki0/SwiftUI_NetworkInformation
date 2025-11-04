
import SwiftUI
import Network
import WiFiAware

struct NetworkMonitorDemo: View {
    @State private var path: NWPath?
    @State private var waPath: WAPath?
    
    var body: some View {
        NavigationStack {
            List {
                if let path = self.path {
                    Section("Network State") {
                        cell("State", content: path.status.description(unsatisfiedReason: path.unsatisfiedReason))
                    }

                    Section("Interfaces") {
                        cell("Available Types", content: path.availableInterfaceTypes.map(\.description).joined(separator: ", "))
                        ForEach(path.availableInterfaces, id: \.self) { interface in
                            let gateways: [NWEndpoint] = path.gatewayForInterface(interface)
                            NavigationLink(destination: {
                                List {
                                    Section(interface.name) {
                                        if gateways.isEmpty {
                                            Text("No gateways configured for the interface.")
                                                .foregroundStyle(.secondary)
                                        }
                                        ForEach(gateways, id: \.self) { gateway in
                                            Text(gateway.description)
                                        }
                                    }
                                }
                            }, label: {
                                Text(interface.description)
                            })
                        }
                    }
                    
                    Section("Capabilities & Properties") {
                        cell("Supports IPv4", content: "\(path.supportsIPv4)")
                        cell("supports IPv6", content: "\(path.supportsIPv6)")
                        cell("Supports DNS", content: "\(path.supportsDNS)")
                        
                        cell("Low Data Mode", content: "\(path.isConstrained)")
                        cell("Constrained by user", content: "\(path.isUltraConstrained)")
                        cell("Expensive", subtitle: "Ex: Cellular or a Personal Hotspot", content: "\(path.isExpensive)")
                        
                        cell("Link Quality", content: "\(path.linkQuality.description)")
                    }
                    
                    Section("Connected Paths") {
                        cell("Local Endpoint", content: "\(path.localEndpoint?.description, default: "No local endpoint")")
                        cell("Remote Endpoint", content: "\(path.remoteEndpoint?.description, default: "No remote endpoint")")
                    }
                    
                    
                    // wifi aware
                    Section("Wifi Aware") {
                        if let waPath = self.waPath {
                            cell("Endpoint", content: "\(waPath.endpoint.description)")
                            cell("Performance Metrics", content: "\(waPath.performance.description(for: .bestEffort))")
                            cell("Duration Active", content: "\(waPath.durationActive.formatted())")

                        } else {
                            Text("Path is not over Wi-Fi Aware.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                }
 
            }
            .task {
                for await path in NWPathMonitor() {
                    self.path = path
                    
                    // only available with import WiFiAware
                    self.waPath = try? await path.wifiAware
                }
            }
            .navigationTitle("Network Information")
        }
    }
    
    @ViewBuilder
    private func cell(_ title: String,  subtitle: String? = nil, content: String) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .fontWeight(.medium)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
                        
            Text(content)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: WA Extensions
extension WAPerformanceReport {
    func description(for assetCategory: WAAccessCategory) -> String {
        let signalStrength: String = if let signal = self.signalStrength { String(format: "%.2f", signal) } else { "(unknown)" }
        let latencyMilliseconds: Double? = self.transmitLatency[assetCategory]?.average?.milliseconds
        let latencyText: String = if let latencyMilliseconds { String(format: "%.2f", latencyMilliseconds) } else { "(unknown)" }
        return "Signal Strength: \(signalStrength)\nTransmit Latency: \(latencyText)"
    }
}

extension Duration {
    // Converts the duration to milliseconds.
    var milliseconds: Double {
        return Double(self.components.seconds * 1000) + Double(self.components.attoseconds) / Double(1_000_000_000_000_000)
    }
}


// MARK: NW Extensions

extension NWPath {
    func gatewayForInterface(_ interface: NWInterface) -> [NWEndpoint] {
        return self.gateways.filter({$0.interface == interface})
    }
    var availableInterfaceTypes: [NWInterface.InterfaceType] {
        return Array(Set(self.availableInterfaces.map(\.type)))
    }
}

extension NWPath.LinkQuality {
    var description: String {
        return switch self {
            
        case .unknown:
            "unknown"
        case .minimal:
            "minimal"
        case .moderate:
            "moderate"
        case .good:
            "good"
        @unknown default:
            "unknown"
        }
    }
}


extension NWPath.Status {
    
    // unsatisfiedReason will be notAvailable if Status is anything other than unsatisfied
    func description(unsatisfiedReason: NWPath.UnsatisfiedReason) -> String {
        return switch self {
        case .satisfied:
            "Available"
        case .unsatisfied:
            unsatisfiedReason == .notAvailable ? "Not available" : "Not available: \(unsatisfiedReason.description)"
        case .requiresConnection:
            "Connecting"
        @unknown default:
            "Unknown"
        }
    }
}

extension NWPath.UnsatisfiedReason {
    var description: String {
        return switch self {
            
        case .notAvailable:
            "Not Available"
        case .cellularDenied:
            "Cellular Denied"
        case .wifiDenied:
            "Wifi Denied"
        case .localNetworkDenied:
            "Local Network Denied"
        case .vpnInactive:
            "VPN Inactive"
        @unknown default:
            "unknown"
        }
    }
}

extension NWInterface {
    var description: String {
        return "\(self.name) [\(self.type.description)]"
    }
}

extension NWInterface.InterfaceType {
    var description: String {
        return switch self {
            
        case .other:
            "Other"
        case .wifi:
            "Wifi"
        case .cellular:
            "cellular"
        case .wiredEthernet:
            "Wired Ethernet"
        case .loopback:
            "Loopback"
        @unknown default:
            "unknown"
        }
        
    }
}


extension NWEndpoint {
    var description: String {
        return switch self {
            
        case .hostPort(host: let host, port: let port):
            "\(host):\(port)"
        case .service(name: let name, type: let type, domain: let domain, interface: _):
            "Bonjour service: \(name) [Domain: \(domain)] [Type: \(type)]"
        case .unix(path: let path):
            "UNIX domain: \(path)"
        case .url(let url):
            "URL: \(url.path(percentEncoded: false))"
        case .opaque(let nwEndpoint):
            "Opaque: \(nwEndpoint)"
        @unknown default:
            "unknown"
        }
    }
}
